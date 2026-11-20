/// The app's side of a workbench connected over the Dart VM service (the
/// just_storage DevTools extension), in debug builds.
@internal
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' show max;

import 'package:flutter/foundation.dart'
    show debugPrint, internal, visibleForTesting;

import 'admin_types.dart';
import 'just_key_value_storage.dart';
import 'just_secure_storage.dart';
import 'storage_change.dart';
import 'workbench_wire.dart';

/// What the platform knows about a storage that a workbench asks for: where
/// it keeps its values, and whether and how it can be wiped.
@internal
typedef StoragePlatformAdmin = ({
  Future<StoreDescription?> Function(JustKeyValueStorage storage) describe,
  bool Function(JustKeyValueStorage storage) canWipe,
  Future<void> Function(JustKeyValueStorage storage) wipe,
});

/// Serves a workbench in another process: the storages the app shows it,
/// one service extension ([workbenchExtension]) that runs [handle], and
/// events ([workbenchListEvent], [workbenchChangeEvent]) while a workbench
/// is connected.
///
/// `JustStorage.standard()` and `JustStorage.encrypted()` show what they
/// open, and `JustStorage.debugShowInDevTools` anything else, in debug
/// builds (unless `JustStorage.debugDevToolsWorkbench` is false). Nothing
/// runs on the app's writes while no workbench is connected.
@internal
abstract final class WorkbenchService {
  /// Whether storages are shown at all (`JustStorage.debugDevToolsWorkbench`).
  static bool enabled = true;

  static bool _registered = false;
  static bool _watching = false;
  static int _sessionCount = 0;
  static final Set<String> _sessions = {};
  static final List<_Shown> _stores = [];

  static final StreamController<(String, Map<String, Object?>)> _events =
      StreamController.broadcast(sync: true);
  static final Map<_Shown, StreamSubscription<StorageChange>> _changeSubs = {};
  static final Map<_Shown, _PendingChanges> _pending = {};

  /// The events posted to connected workbenches: (kind, data).
  static Stream<(String, Map<String, Object?>)> get events => _events.stream;

  /// How long changes of one storage are gathered into one event; zero
  /// sends each at once (tests).
  @visibleForTesting
  static Duration changeDelay = defaultChangeDelay;

  /// [changeDelay] unless a test changes it.
  static const Duration defaultChangeDelay = Duration(milliseconds: 100);

  /// The names of the storages shown, in order.
  @visibleForTesting
  static List<String> get storeNames => [for (final s in _stores) s.name];

  // ---------------------------------------------------------------------------
  // What is shown
  // ---------------------------------------------------------------------------

  /// Shows [storage] — one `JustStorage` opened — as [name], or as
  /// "[name] 2" and so on when another storage has that name. Does nothing
  /// when it is shown already.
  static void track(
    JustKeyValueStorage storage, {
    required String name,
    String? description,
    required StoragePlatformAdmin platform,
  }) {
    if (!enabled || _stores.any((s) => identical(s.storage, storage))) return;
    var unique = name;
    for (var n = 2; _stores.any((s) => s.name == unique); n++) {
      unique = '$name $n';
    }
    final shown = _Shown(unique, storage, description, platform);
    _stores.add(shown);
    _added(shown);
  }

  /// Shows [storage] as [name], where the storage of that name was, or
  /// renamed where [storage] was; else after the others.
  static void show(
    String name,
    JustKeyValueStorage storage, {
    String? description,
    required StoragePlatformAdmin platform,
  }) {
    if (!enabled) return;
    final at = _stores.indexWhere(
      (s) => s.name == name || identical(s.storage, storage),
    );
    final gone = [
      for (final s in _stores)
        if (s.name == name || identical(s.storage, storage)) s,
    ];
    for (final s in gone) {
      _stores.remove(s);
      _forget(s);
    }
    final shown = _Shown(name, storage, description, platform);
    _stores.insert(at < 0 ? _stores.length : at, shown);
    _added(shown);
  }

  static void _added(_Shown shown) {
    register();
    if (!_watching) return;
    _follow(shown);
    _events.add((workbenchListEvent, const {}));
  }

  // ---------------------------------------------------------------------------
  // The service extension
  // ---------------------------------------------------------------------------

  /// Registers the service extension (once per isolate) and says in the
  /// console how to open the workbench.
  static void register() {
    if (_registered) return;
    _registered = true;
    try {
      developer.registerExtension(workbenchExtension, (_, params) async {
        Map<String, Object?> args;
        try {
          final decoded = jsonDecode(params['args'] ?? '{}');
          args = decoded is Map<String, Object?> ? decoded : const {};
        } on FormatException {
          args = const {};
        }
        final reply = await handle(params['method'] ?? '', args);
        return developer.ServiceExtensionResponse.result(jsonEncode(reply));
      });
    } on ArgumentError {
      return; // registered already (by an earlier copy of this code)
    }
    _events.stream.listen((e) => developer.postEvent(e.$1, e.$2));
    unawaited(_announce());
  }

  static Future<void> _announce() async {
    final developer.ServiceProtocolInfo info;
    try {
      info = await developer.Service.getInfo();
    } on UnsupportedError {
      return; // the web: the app can't learn its address (DevTools still can)
    }
    final uri = info.serverUri;
    final ws = info.serverWebSocketUri;
    if (uri == null || ws == null) return; // no VM service: nothing connects
    debugPrint(
      workbenchBanner(
        uri.resolve('devtools/$workbenchScreen?uri=$ws').toString(),
      ),
    );
  }

  /// The DevTools screen of the extension (DevTools names it after the
  /// package).
  static const String workbenchScreen = 'just_storage_ext';

  /// What the console says when the service starts: [link] opens the
  /// workbench in the DevTools that `flutter run` serves.
  @visibleForTesting
  static String workbenchBanner(String link) {
    final lines = [
      'Just Storage workbench (debug builds)',
      null,
      'Open it in Flutter DevTools, the "just_storage" tab:',
      link,
      'On a phone or emulator, open the DevTools link flutter run',
      'prints instead and choose that tab. Enable it when asked.',
    ];
    final width = [for (final l in lines) l?.length ?? 0].reduce(max) + 2;
    return [
      '╔${'═' * width}╗',
      for (final l in lines)
        l == null ? '╟${'─' * width}╢' : '║ ${l.padRight(width - 2)} ║',
      '╚${'═' * width}╝',
    ].join('\n');
  }

  /// Runs the workbench call [method] with [args] (decoded JSON). The reply
  /// is `{'ok': true, ...}` or `{'ok': false, 'error': ...}`
  /// (see [encodeError]).
  static Future<Map<String, Object?>> handle(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      return {'ok': true, ...await _dispatch(method, args)};
    } catch (e) {
      return {'ok': false, 'error': encodeError(e)};
    }
  }

  static Future<Map<String, Object?>> _dispatch(
    String method,
    Map<String, Object?> args,
  ) async {
    if (_watching) _followAll();
    switch (method) {
      case 'connect':
        final session = 'w${++_sessionCount}';
        _sessions.add(session);
        _watch();
        return {
          'protocol': workbenchProtocol,
          'version': justStorageVersion,
          'session': session,
        };
      case 'disconnect':
        _sessions.remove(args['session']);
        if (_sessions.isEmpty) await _unwatch();
        return const {};
      case 'list':
        return {
          'stores': [for (final s in _stores) _info(s).toJson()],
        };
      case 'readAll':
        return {'entries': await _store(args).storage.readAll()};
      case 'read':
        return {'value': await _store(args).storage.read(_string(args, 'key'))};
      case 'containsKey':
        return {
          'value': await _store(args).storage.containsKey(_string(args, 'key')),
        };
      case 'write':
        await _store(
          args,
        ).storage.write(_string(args, 'key'), _string(args, 'value'));
        return const {};
      case 'delete':
        final storage = _store(args).storage;
        final keys = args['keys'];
        if (keys is! List) {
          throw ArgumentError('the workbench call needs "keys"');
        }
        await Future.wait([for (final key in keys) storage.delete('$key')]);
        return const {};
      case 'clear':
        await _store(args).storage.clear();
        return const {};
      case 'wipe':
        final s = _store(args);
        if (!s.platform.canWipe(s.storage)) {
          throw StateError('"${s.name}" can\'t be wiped.');
        }
        await s.platform.wipe(s.storage);
        return const {};
      case 'describe':
        final s = _store(args);
        final description = await s.platform.describe(s.storage);
        return {
          'description': description == null
              ? null
              : encodeDescription(description),
        };
      default:
        throw ArgumentError('unknown workbench call "$method"');
    }
  }

  static WorkbenchStoreInfo _info(_Shown s) => WorkbenchStoreInfo(
    name: s.name,
    description: s.description,
    secure: s.storage is JustSecureStorage,
    canWipe: s.platform.canWipe(s.storage),
    type: '${s.storage.runtimeType}',
  );

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /// Starts posting events (when a workbench connects).
  static void _watch() {
    _watching = true;
    _followAll();
  }

  static void _followAll() {
    for (final s in _stores) {
      _follow(s);
    }
  }

  /// Listens to [s]'s changes, unless already. A storage that was disposed
  /// ended its stream: it is listened to again at the next call.
  static void _follow(_Shown s) {
    if (_changeSubs.containsKey(s)) return;
    _changeSubs[s] = s.storage.changes.listen(
      (change) => _gather(s, change),
      onError: (Object _) {},
      onDone: () => _changeSubs.remove(s),
    );
  }

  /// Gathers [change] into one event per [changeDelay], so an app that
  /// writes every frame sends a few events a second, not one per write;
  /// a key changed twice in that time is sent once, with its last value.
  static void _gather(_Shown s, StorageChange change) {
    final pending = _pending.putIfAbsent(s, _PendingChanges.new);
    final key = change.key;
    if (key == null) {
      pending
        ..cleared = true
        ..values.clear();
    } else {
      pending.values
        ..remove(key)
        ..[key] = change.value;
    }
    if (changeDelay == Duration.zero) {
      _send(s);
    } else {
      pending.timer ??= Timer(changeDelay, () => _send(s));
    }
  }

  static void _send(_Shown s) {
    final pending = _pending.remove(s);
    if (pending == null || !_watching || !_stores.contains(s)) return;
    _events.add((
      workbenchChangeEvent,
      {
        'store': s.name,
        'changes': [
          if (pending.cleared) encodeChange(const StorageChange.cleared()),
          for (final MapEntry(:key, :value) in pending.values.entries)
            encodeChange(StorageChange(key, value)),
        ],
      },
    ));
  }

  /// Stops listening to [s] (it is no longer shown).
  static void _forget(_Shown s) {
    unawaited(_changeSubs.remove(s)?.cancel());
    _pending.remove(s)?.timer?.cancel();
  }

  /// Stops posting events (when the last workbench disconnects): an app
  /// nobody watches does no work for workbenches.
  static Future<void> _unwatch() async {
    _watching = false;
    final subs = [..._changeSubs.values];
    _changeSubs.clear();
    for (final p in _pending.values) {
      p.timer?.cancel();
    }
    _pending.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
  }

  /// Stops posting events, ends every session and forgets what is shown
  /// (tests).
  @visibleForTesting
  static Future<void> reset() async {
    await _unwatch();
    _sessions.clear();
    _stores.clear();
    changeDelay = defaultChangeDelay;
  }

  // ---------------------------------------------------------------------------
  // Arguments
  // ---------------------------------------------------------------------------

  static String _string(Map<String, Object?> args, String key) {
    final v = args[key];
    if (v is String) return v;
    throw ArgumentError('the workbench call needs "$key"');
  }

  static _Shown _store(Map<String, Object?> args) {
    final name = _string(args, 'store');
    for (final s in _stores) {
      if (s.name == name) return s;
    }
    throw StateError(
      'The app no longer shows "$name" (was it restarted?); refresh the '
      'workbench.',
    );
  }
}

/// A storage shown to workbenches.
final class _Shown {
  _Shown(this.name, this.storage, this.description, this.platform);

  final String name;
  final JustKeyValueStorage storage;
  final String? description;
  final StoragePlatformAdmin platform;
}

/// Changes of one storage waiting to be sent: a clear, then each key's last
/// value (null when deleted), in the order they last changed.
final class _PendingChanges {
  bool cleared = false;
  final Map<String, String?> values = {};
  Timer? timer;
}
