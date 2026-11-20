import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/core.dart';
import '../core/value_watchers.dart';
import 'just_storage.dart';

/// [JustStandardStorage] for the web: the browser's `localStorage`, each
/// value under its key with the prefix `just_storage:`.
///
/// Reads go to `localStorage` every time, so they see what other tabs of
/// the page wrote; [watch] streams hear those writes too. `localStorage`
/// holds about 5 MB per origin; a write past that throws a
/// [StorageException].
///
/// Get one from [JustStorage.standard].
class WebStorage extends JustStandardStorage {
  /// A storage over this page's `localStorage`.
  ///
  /// Prefer [JustStorage.standard], which hands everyone the same instance.
  WebStorage();

  /// What every key is stored under: `just_storage:<key>`.
  static const String prefix = 'just_storage:';

  final ValueWatchers _watchers = ValueWatchers();
  late final ChangeListeners _changes = ChangeListeners(
    onListen: _listenToOtherTabs,
  );
  StreamSubscription<web.StorageEvent>? _otherTabs;

  static web.Storage get _local {
    try {
      return web.window.localStorage;
    } catch (e) {
      throw StorageException('localStorage is not available here.', cause: e);
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      return _local.getItem('$prefix$key');
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not read "$key".', cause: e);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      _local.setItem('$prefix$key', value);
    } on StorageException {
      rethrow;
    } catch (e) {
      // QuotaExceededError, most often.
      throw StorageException('Could not write "$key".', cause: e);
    }
    _watchers.changed(key, value);
    _changes.add(StorageChange(key, value));
  }

  @override
  Future<void> delete(String key) async {
    try {
      _local.removeItem('$prefix$key');
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not delete "$key".', cause: e);
    }
    _watchers.changed(key, null);
    _changes.add(StorageChange(key, null));
  }

  @override
  Future<void> clear() async {
    final removed = <String>[];
    try {
      final local = _local;
      for (final name in _names(local)) {
        local.removeItem(name);
        removed.add(name.substring(prefix.length));
      }
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not clear the storage.', cause: e);
    }
    for (final key in {...removed, ..._watchers.keys}) {
      _watchers.changed(key, null);
    }
    _changes.add(const StorageChange.cleared());
  }

  @override
  Future<bool> containsKey(String key) async => await read(key) != null;

  @override
  Future<Map<String, String>> readAll() async {
    try {
      final local = _local;
      return Map.unmodifiable(<String, String>{
        for (final name in _names(local))
          name.substring(prefix.length): ?local.getItem(name),
      });
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not read the storage.', cause: e);
    }
  }

  @override
  Stream<String?> watch(String key) {
    _listenToOtherTabs();
    return _watchers.watch(
      key,
      load: () async {},
      now: () => _local.getItem('$prefix$key'),
    );
  }

  @override
  Stream<StorageChange> get changes => _changes.stream;

  /// Ends every [watch] and [changes] stream and stops listening to other
  /// tabs. The storage still works afterwards.
  Future<void> dispose() async {
    await _otherTabs?.cancel();
    _otherTabs = null;
    _watchers.closeAll();
    _changes.closeAll();
  }

  /// The prefixed names in [local], listed before any is removed.
  static List<String> _names(web.Storage local) => [
    for (var i = 0; i < local.length; i++)
      if (local.key(i) case final name? when name.startsWith(prefix)) name,
  ];

  void _listenToOtherTabs() {
    _otherTabs ??= web.EventStreamProviders.storageEvent
        .forTarget(web.window)
        .listen(_onOtherTab);
  }

  /// Another tab of the page changed `localStorage`.
  void _onOtherTab(web.StorageEvent event) {
    final area = event.storageArea;
    if (area == null || !area.strictEquals(_local).toDart) return;
    final name = event.key;
    if (name == null) {
      // It was cleared: everyone watching gets what is left.
      for (final key in [..._watchers.keys]) {
        _watchers.changed(key, area.getItem('$prefix$key'));
      }
      _changes.add(const StorageChange.cleared());
    } else if (name.startsWith(prefix)) {
      final key = name.substring(prefix.length);
      _watchers.changed(key, event.newValue);
      _changes.add(StorageChange(key, event.newValue));
    }
  }
}
