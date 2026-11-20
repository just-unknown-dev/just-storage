import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/core.dart';
import '../file/admin_support.dart'
    if (dart.library.js_interop) '../web/admin_support.dart'
    as platform;
import '../file/file.dart' if (dart.library.js_interop) '../web/web.dart';
import 'admin_utils.dart' as utils;
import 'just_storage_admin_screen.dart';
import 'store_view.dart';

/// A storage [JustStorageAdminScreen] shows: a [name] for it, and the
/// storage itself or how to open it.
///
/// ```dart
/// JustStorageAdminScreen(stores: [
///   StorageAdminStore.standard(),
///   StorageAdminStore.secure(),
///   StorageAdminStore('Settings', settingsStorage),
/// ])
/// ```
final class StorageAdminStore {
  /// [storage], shown as [name]. A [JustSecureStorage]'s values are hidden
  /// until shown.
  StorageAdminStore(this.name, JustKeyValueStorage storage, {this.description})
    : isSecure = storage is JustSecureStorage,
      _open = (() async => storage);

  /// The app's `JustStorage.standard()`, opened when the screen first
  /// reads it.
  StorageAdminStore.standard({
    this.name = 'Standard',
    this.description = 'JustStorage.standard(): plain values',
  }) : isSecure = false,
       _open = JustStorage.standard;

  /// The app's `JustStorage.encrypted()`, opened when the screen first
  /// reads it. Its values are hidden until shown.
  StorageAdminStore.secure({
    this.name = 'Secure',
    this.description = 'JustStorage.encrypted(): AES-256-GCM',
  }) : isSecure = true,
       _open = JustStorage.encrypted;

  /// What the screen calls it; unique among a screen's storages.
  final String name;

  /// A line about what it holds, shown under its name.
  final String? description;

  /// Whether its values are secret: hidden until shown, and exported only
  /// after a warning.
  final bool isSecure;

  final Future<JustKeyValueStorage> Function() _open;

  @override
  String toString() => 'StorageAdminStore($name)';
}

/// The state of [JustStorageAdminScreen]: the storages it shows, what they
/// hold, which is selected, and the changes it makes.
///
/// It follows each storage's [JustKeyValueStorage.changes], so what the app
/// writes while the screen is open shows up straight away. Pass one to
/// [JustStorageAdminScreen.controller] to share it, or to drive the screen
/// from code; it doesn't dispose the storages.
///
/// Methods that change a storage throw what the storage throws, and a
/// [StateError] when [readOnly].
class StorageAdminController extends ChangeNotifier {
  /// A controller over [stores] — by default the app's standard and secure
  /// storages. With [readOnly] nothing can be changed through it.
  StorageAdminController({
    List<StorageAdminStore>? stores,
    this.readOnly = false,
  }) : stores = List.unmodifiable(
         stores ?? [StorageAdminStore.standard(), StorageAdminStore.secure()],
       ) {
    final names = <String>{};
    for (final store in this.stores) {
      if (!names.add(store.name)) {
        throw ArgumentError.value(
          store.name,
          'stores',
          'Two storages share this name',
        );
      }
      _states[store] = _StoreState(store);
    }
    _selected = this.stores.firstOrNull;
  }

  /// The storages shown, in order.
  final List<StorageAdminStore> stores;

  /// Whether nothing can be changed: no writing, deleting, clearing or
  /// importing. Looking, searching, copying and exporting still work.
  final bool readOnly;

  final Map<StorageAdminStore, _StoreState> _states = {};
  StorageAdminStore? _selected;
  String? _selectedKey;
  int _busy = 0;
  bool _disposed = false;
  Timer? _fadeTimer;

  /// Marks recent changes: those marked with a generation up to the one
  /// [_fadeTimer] was started at go when it fires.
  int _generation = 0;

  /// How long a changed entry stays marked as changed, at least: a change
  /// made while an earlier one is marked stays until the next fade, up to
  /// twice as long.
  static const Duration recentChange = Duration(seconds: 3);

  _StoreState _stateOf(StorageAdminStore store) {
    final state = _states[store];
    if (state == null) {
      throw ArgumentError.value(store, 'store', 'Not one of this screen\'s');
    }
    return state;
  }

  // ---------------------------------------------------------------------------
  // What the screen shows
  // ---------------------------------------------------------------------------

  /// The storage called [name], or null.
  StorageAdminStore? storeNamed(String name) =>
      stores.where((s) => s.name == name).firstOrNull;

  /// Whether a read or a change is under way.
  bool get isBusy => _busy > 0;

  /// The entries of [store] as last read: empty until it is read, and when
  /// it can't be.
  Map<String, String> entriesOf(StorageAdminStore store) =>
      _stateOf(store).entries;

  /// What went wrong reading [store]; null when it was read.
  Object? errorOf(StorageAdminStore store) => _stateOf(store).error;

  /// Whether [store] has been read, or has failed to be.
  bool isLoaded(StorageAdminStore store) => _stateOf(store).loaded;

  /// Whether [store] can be wiped: emptied with its key destroyed, so not
  /// even a copy of what it held can be decrypted again.
  bool canWipe(StorageAdminStore store) {
    final storage = _stateOf(store).storage;
    return storage != null && platform.canWipe(storage);
  }

  /// The storage selected; the first one at the start.
  StorageAdminStore? get selectedStore => _selected;

  /// The key selected in [selectedStore], if any. It may name a key that
  /// has since been deleted.
  String? get selectedKey => _selectedKey;

  /// Selects [store], and [key] in it.
  void select(StorageAdminStore store, {String? key}) {
    _stateOf(store);
    if (store == _selected && key == _selectedKey) return;
    _selected = store;
    _selectedKey = key;
    _notify();
    if (!isLoaded(store)) unawaited(refresh(store));
  }

  /// Selects [key] in [selectedStore]; null selects none.
  void selectKey(String? key) {
    if (key == _selectedKey) return;
    _selectedKey = key;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // For the screen
  // ---------------------------------------------------------------------------

  /// How [store]'s entries are shown.
  @internal
  StoreView viewOf(StorageAdminStore store) => _stateOf(store).view;

  /// What kind of value [value], under [key] in [store], is; remembered
  /// while the value stays the same.
  @internal
  utils.ValueKind kindOf(StorageAdminStore store, String key, String value) {
    final kinds = _stateOf(store).kinds;
    final known = kinds[key];
    if (known != null && identical(known.$1, value)) return known.$2;
    final kind = utils.kindOf(value);
    kinds[key] = (value, kind);
    return kind;
  }

  /// When [key] of [store] last changed, while it is marked as a recent
  /// change (see [recentChange]); null otherwise.
  @internal
  DateTime? changedAt(StorageAdminStore store, String key) =>
      _stateOf(store).changedAt[key]?.at;

  /// How many times [store] has been read: a new number means new data.
  @internal
  int revisionOf(StorageAdminStore store) => _stateOf(store).revision;

  /// [store]'s storage once opened, else null.
  @internal
  JustKeyValueStorage? storageOf(StorageAdminStore store) =>
      _stateOf(store).storage;

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// Reads [store] again, or every storage when null. Never throws: what
  /// goes wrong is [errorOf] the storage.
  Future<void> refresh([StorageAdminStore? store]) async {
    final targets = store == null ? _states.values.toList() : [_stateOf(store)];
    _busy++;
    _notify();
    try {
      await Future.wait([for (final s in targets) _read(s)]);
    } finally {
      _busy--;
      _notify();
    }
  }

  Future<JustKeyValueStorage> _open(_StoreState s) async {
    final open = s.storage;
    if (open != null) return open;
    final opening = s.opening ??= s.store._open();
    try {
      final storage = await opening;
      s.storage = storage;
      return storage;
    } catch (_) {
      // Try again next time.
      if (identical(s.opening, opening)) s.opening = null;
      rethrow;
    }
  }

  Future<void> _read(_StoreState s) async {
    try {
      final storage = await _open(s);
      _follow(s, storage);
      s.entries = await storage.readAll();
      s.error = null;
    } catch (e) {
      s.entries = const {};
      s.error = e;
    } finally {
      s.loaded = true;
      s.revision++;
      s.kinds.removeWhere((key, _) => !s.entries.containsKey(key));
      s.view.keepOnly(s.entries.keys.toSet());
    }
  }

  /// Listens to [storage]'s changes, once.
  void _follow(_StoreState s, JustKeyValueStorage storage) {
    if (s.changes != null || _disposed) return;
    s.changes = storage.changes.listen(
      (change) => _onChange(s, change),
      onError: (Object _) => _scheduleRead(s),
      onDone: () => s.changes = null,
    );
  }

  void _onChange(_StoreState s, StorageChange change) {
    if (_disposed) return;
    final key = change.key;
    if (key != null) {
      s.changedAt[key] = (at: DateTime.now(), generation: _generation);
    }
    _scheduleRead(s);
    _scheduleFade();
  }

  /// Reads [s] again shortly: a burst of changes costs one read.
  void _scheduleRead(_StoreState s) {
    s.readTimer?.cancel();
    s.readTimer = Timer(const Duration(milliseconds: 100), () async {
      if (_disposed) return;
      await _read(s);
      _notify();
    });
  }

  /// Clears the marks of the changes made so far after [recentChange],
  /// and then those made since, in turn.
  void _scheduleFade() {
    if (_fadeTimer != null || _disposed) return;
    final fading = _generation++;
    _fadeTimer = Timer(recentChange, () {
      _fadeTimer = null;
      var more = false;
      for (final s in _states.values) {
        s.changedAt.removeWhere((_, mark) => mark.generation <= fading);
        more |= s.changedAt.isNotEmpty;
      }
      _notify();
      if (more) _scheduleFade();
    });
  }

  // ---------------------------------------------------------------------------
  // Changing
  // ---------------------------------------------------------------------------

  void _checkWritable() {
    if (readOnly) throw StateError('This admin screen is read-only.');
  }

  /// Runs [action] on [store]'s storage, then reads it again — after a
  /// failure too, to show what it holds now.
  Future<T> _change<T>(
    StorageAdminStore store,
    Future<T> Function(JustKeyValueStorage storage, _StoreState s) action,
  ) async {
    _checkWritable();
    final s = _stateOf(store);
    _busy++;
    _notify();
    try {
      return await action(await _open(s), s);
    } finally {
      await _read(s);
      _busy--;
      _notify();
    }
  }

  /// Stores [value] under [key] in [store], replacing what was there.
  Future<void> write(StorageAdminStore store, String key, String value) =>
      _change(store, (storage, _) => storage.write(key, value));

  /// Removes [keys] from [store].
  Future<void> delete(StorageAdminStore store, Iterable<String> keys) {
    final removing = keys.toSet();
    return _change(store, (storage, s) async {
      await Future.wait([for (final key in removing) storage.delete(key)]);
      if (store == _selected && removing.contains(_selectedKey)) {
        _selectedKey = null;
      }
    });
  }

  /// Moves the value of [from] to [to] in [store]. Throws a [StateError]
  /// when [to] holds a value already, or [from] holds none.
  Future<void> rename(StorageAdminStore store, String from, String to) {
    if (from == to) return Future.value();
    return _change(store, (storage, s) async {
      if (await storage.containsKey(to)) {
        throw StateError('"$to" already holds a value.');
      }
      final value = await storage.read(from);
      if (value == null) throw StateError('"$from" holds no value.');
      // The new key first: a failure leaves the old one as it was.
      await storage.write(to, value);
      await storage.delete(from);
      if (store == _selected && _selectedKey == from) _selectedKey = to;
    });
  }

  /// Copies the value of [from] to the new key [to] in [store]. Throws a
  /// [StateError] when [to] holds a value already, or [from] holds none.
  Future<void> copy(StorageAdminStore store, String from, String to) =>
      _change(store, (storage, _) async {
        if (await storage.containsKey(to)) {
          throw StateError('"$to" already holds a value.');
        }
        final value = await storage.read(from);
        if (value == null) throw StateError('"$from" holds no value.');
        await storage.write(to, value);
      });

  /// Removes every entry of [store] — of one that can't be read, too.
  Future<void> clear(StorageAdminStore store) =>
      _change(store, (storage, s) async {
        await storage.clear();
        s.view.clearChecked();
        if (store == _selected) _selectedKey = null;
      });

  /// Removes every entry of [store] and destroys its key (see [canWipe]):
  /// nothing it held can be decrypted again, even from a copy. The next
  /// write makes a new key.
  Future<void> wipe(StorageAdminStore store) =>
      _change(store, (storage, s) async {
        if (!platform.canWipe(storage)) {
          throw StateError('"${store.name}" can\'t be wiped.');
        }
        await platform.wipeStorage(storage);
        s.view.clearChecked();
        if (store == _selected) _selectedKey = null;
      });

  /// Writes [entries] into [store] and returns how many were written.
  ///
  /// With [clearFirst] the storage is emptied before. Otherwise a key that
  /// holds a value keeps it unless [replaceExisting].
  Future<int> importEntries(
    StorageAdminStore store,
    Map<String, String> entries, {
    bool replaceExisting = true,
    bool clearFirst = false,
  }) => _change(store, (storage, _) async {
    if (clearFirst) await storage.clear();
    final existing = clearFirst
        ? const <String, String>{}
        : await storage.readAll();
    final writing = {
      for (final MapEntry(:key, :value) in entries.entries)
        if (replaceExisting || !existing.containsKey(key)) key: value,
    };
    await Future.wait([
      for (final MapEntry(:key, :value) in writing.entries)
        storage.write(key, value),
    ]);
    return writing.length;
  });

  /// [store]'s entries — only [keys] when given — as the JSON the screen
  /// exports and imports: the entries under `"entries"`, with the
  /// storage's name and the time.
  String exportJson(StorageAdminStore store, {Iterable<String>? keys}) {
    final all = entriesOf(store);
    final chosen = keys == null
        ? all
        : {for (final key in keys) key: ?all[key]};
    return utils.buildExport(
      store: store.name,
      secure: store.isSecure,
      entries: chosen,
    );
  }

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _fadeTimer?.cancel();
    for (final s in _states.values) {
      s.readTimer?.cancel();
      unawaited(s.changes?.cancel());
      s.changes = null;
      s.view.dispose();
    }
    super.dispose();
  }

  /// Tells listeners, unless disposed: a read can finish after the screen
  /// has gone.
  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// What the controller knows of one storage.
final class _StoreState {
  _StoreState(this.store) : view = StoreView(secure: store.isSecure);

  final StorageAdminStore store;
  final StoreView view;
  JustKeyValueStorage? storage;
  Future<JustKeyValueStorage>? opening;
  Map<String, String> entries = const {};
  Object? error;
  bool loaded = false;
  int revision = 0;
  StreamSubscription<StorageChange>? changes;
  Timer? readTimer;
  final Map<String, ({DateTime at, int generation})> changedAt = {};
  final Map<String, (String, utils.ValueKind)> kinds = {};
}
