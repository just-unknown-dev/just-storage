/// The workbench on the storages of a running app it is connected to (the
/// just_storage DevTools extension), through the app's workbench service.
@internal
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show internal;

import '../../core/admin_types.dart';
import '../../core/core.dart';
import '../../core/workbench_wire.dart';
import '../storage_admin_controller.dart';

/// How a remote workbench reaches the app.
@internal
abstract interface class WorkbenchTransport {
  /// Calls the workbench service's [method] in the app with [args] (JSON).
  /// Returns its reply: `{'ok': true, ...}` or `{'ok': false, 'error': ...}`.
  Future<Map<String, Object?>> call(String method, Map<String, Object?> args);

  /// The app's workbench events: (kind, data).
  Stream<(String, Map<String, Object?>)> get events;
}

/// The storages of an app reached through [transport], as
/// [StorageAdminStore]s over [RemoteStorage]s.
@internal
final class RemoteStorageHost {
  /// A host over [transport]; it connects with the first call.
  RemoteStorageHost(this.transport) {
    _eventSub = transport.events.listen(_onEvent);
  }

  /// How the app is reached.
  final WorkbenchTransport transport;

  late final StreamSubscription<(String, Map<String, Object?>)> _eventSub;
  final StreamController<void> _storesChanged = StreamController.broadcast();
  final Map<String, ({StorageAdminStore store, RemoteStorage storage})>
  _stores = {};
  Future<String>? _session;
  bool _disposed = false;

  /// The app's just_storage version, once connected.
  String? appVersion;

  /// Fires when the app shows another storage: call [listStores] again.
  Stream<void> get storesChanged => _storesChanged.stream;

  Future<String> _connect() => _session ??= () async {
    try {
      final reply = await _call('connect', const {});
      final protocol = reply['protocol'];
      if (protocol != workbenchProtocol) {
        throw StateError(
          'The app speaks workbench protocol $protocol (just_storage '
          '${reply['version']}); this workbench speaks $workbenchProtocol. '
          'Use the workbench of the just_storage version the app uses.',
        );
      }
      appVersion = reply['version'] as String?;
      return reply['session'] as String;
    } catch (_) {
      _session = null; // the next call tries again
      rethrow;
    }
  }();

  /// Calls [method] in the app; throws the error it reports.
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> args,
  ) async {
    final session = await _connect();
    return _call(method, {...args, 'session': session});
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> args,
  ) async {
    if (_disposed) throw StateError('The workbench was closed.');
    final reply = await transport.call(method, args);
    if (reply['ok'] == true) return reply;
    final error = reply['error'];
    throw error is Map<String, Object?>
        ? decodeError(error)
        : const WorkbenchRemoteError('The app did not answer the workbench.');
  }

  /// The storages the app shows, in its order. A storage keeps its
  /// [StorageAdminStore] from one listing to the next while it stays the
  /// same.
  Future<List<StorageAdminStore>> listStores() async {
    final reply = await call('list', const {});
    final infos = [
      for (final json in reply['stores'] as List? ?? const [])
        if (json is Map<String, Object?>) WorkbenchStoreInfo.fromJson(json),
    ];
    final names = {for (final info in infos) info.name};
    _stores.removeWhere((name, known) {
      if (names.contains(name)) return false;
      known.storage._close();
      return true;
    });
    return [for (final info in infos) storeOf(info)];
  }

  /// The store for [info]: the one known by its name while it is the same
  /// kind of storage, else a new one.
  StorageAdminStore storeOf(WorkbenchStoreInfo info) {
    final known = _stores[info.name];
    if (known != null &&
        known.storage.info.secure == info.secure &&
        known.store.description == info.description) {
      known.storage.info = info;
      return known.store;
    }
    known?.storage._close();
    final storage = info.secure
        ? RemoteSecureStorage._(this, info)
        : RemoteStandardStorage._(this, info);
    final store = StorageAdminStore(
      info.name,
      storage,
      description: info.description,
    );
    _stores[info.name] = (store: store, storage: storage);
    return store;
  }

  /// The remote storage of the store called [name], from the last
  /// listing.
  RemoteStorage? storageNamed(String name) => _stores[name]?.storage;

  void _onEvent((String, Map<String, Object?>) event) {
    if (_disposed) return;
    final (kind, data) = event;
    switch (kind) {
      case workbenchListEvent:
        _storesChanged.add(null);
      case workbenchChangeEvent:
        final name = data['store'];
        final remote = name is String ? _stores[name]?.storage : null;
        if (remote == null) return;
        for (final change in data['changes'] as List? ?? const []) {
          if (change is Map<String, Object?>) {
            remote._changes.add(decodeChange(change));
          }
        }
    }
  }

  /// Ends the session: the app stops sending events once no workbench is
  /// connected.
  void dispose() {
    if (_disposed) return;
    final session = _session;
    _disposed = true;
    unawaited(_eventSub.cancel());
    unawaited(_storesChanged.close());
    for (final known in _stores.values) {
      known.storage._close();
    }
    _stores.clear();
    if (session != null) {
      unawaited(
        session
            .then((s) => transport.call('disconnect', {'session': s}))
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}

/// A storage of the app, reached through [host]: each call is a call to
/// the app, and [changes] are the changes it reports.
@internal
mixin RemoteStorage on JustKeyValueStorage {
  /// How the app is reached.
  RemoteStorageHost get host;

  /// What the app says about this storage.
  WorkbenchStoreInfo get info;
  set info(WorkbenchStoreInfo value);

  final StreamController<StorageChange> _changes = StreamController.broadcast();

  Future<Map<String, Object?>> _ask(
    String method, [
    Map<String, Object?> args = const {},
  ]) => host.call(method, {...args, 'store': info.name});

  @override
  Future<String?> read(String key) async =>
      (await _ask('read', {'key': key}))['value'] as String?;

  @override
  Future<void> write(String key, String value) =>
      _ask('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) => _ask('delete', {
    'keys': [key],
  });

  @override
  Future<void> clear() => _ask('clear');

  @override
  Future<bool> containsKey(String key) async =>
      (await _ask('containsKey', {'key': key}))['value'] == true;

  @override
  Future<Map<String, String>> readAll() async {
    final entries = (await _ask('readAll'))['entries'];
    return Map.unmodifiable({
      if (entries is Map<String, Object?>)
        for (final MapEntry(:key, :value) in entries.entries) key: '$value',
    });
  }

  @override
  Stream<String?> watch(String key) => Stream<String?>.multi((controller) {
    final sub =
        changes
            .where((change) => change.isClear || change.key == key)
            .map((change) => change.value)
            .listen(controller.add, onError: controller.addError)
          ..pause();
    read(key).then(controller.add, onError: controller.addError).whenComplete(
      () {
        if (!controller.isClosed) sub.resume();
      },
    );
    controller.onCancel = sub.cancel;
  }, isBroadcast: true);

  @override
  Stream<StorageChange> get changes => _changes.stream;

  /// Where and how the app keeps the values, as its platform tells.
  Future<StoreDescription?> describe() async {
    final json = (await _ask('describe'))['description'];
    return json is Map<String, Object?> ? decodeDescription(json) : null;
  }

  /// Empties the storage and destroys its key (see [WorkbenchStoreInfo.canWipe]).
  Future<void> wipe() => _ask('wipe');

  void _close() => unawaited(_changes.close());
}

/// A [JustStandardStorage] of the app.
@internal
final class RemoteStandardStorage extends JustStandardStorage
    with RemoteStorage {
  RemoteStandardStorage._(this.host, this.info);

  @override
  final RemoteStorageHost host;

  @override
  WorkbenchStoreInfo info;
}

/// A [JustSecureStorage] of the app.
@internal
final class RemoteSecureStorage extends JustSecureStorage with RemoteStorage {
  RemoteSecureStorage._(this.host, this.info);

  @override
  final RemoteStorageHost host;

  @override
  WorkbenchStoreInfo info;
}
