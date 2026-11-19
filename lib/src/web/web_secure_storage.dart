import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../core/core.dart';
import '../core/sealed_value.dart';
import '../core/value_watchers.dart';
import 'just_storage.dart';
import 'web_aes_gcm_cipher.dart';
import 'web_key_store.dart';

/// [JustSecureStorage] for the web: every value encrypted with AES-256-GCM
/// by the browser's Web Crypto API, in `localStorage` under its key with the
/// prefix `just_secure:`.
///
/// Each value is encrypted on its own, with a random 12-byte nonce and its
/// key as additional authenticated data, as
/// `{"v": 2, "n": <base64 nonce>, "ct": <base64 ciphertext + tag>}`.
///
/// The key is a non-extractable `CryptoKey` kept in IndexedDB: scripts on
/// the page can use it, but can't read it, so a copy of `localStorage`
/// taken elsewhere can't be decrypted. Any script running on the page can
/// still ask for the values, as this class does, so this protects against
/// copies, not against code on the page. Where IndexedDB is unavailable the
/// key is kept raw in `localStorage`, as before 2.0.0. Web Crypto works only
/// on secure pages (`https:` and `localhost`).
///
/// The values are read once and kept in memory. Writes are saved one at a
/// time, in order. What another tab of the page writes reaches this tab's
/// copy, and its [watch] streams, through the browser's `storage` event.
///
/// Values that can't be decrypted make every call throw a
/// [StorageCorruptException] and are left alone, until [clear].
///
/// Get one from [JustStorage.encrypted].
class WebSecureStorage extends JustSecureStorage {
  /// A storage over this page's `localStorage` and IndexedDB.
  ///
  /// Prefer [JustStorage.encrypted], which hands everyone the same
  /// instance.
  WebSecureStorage();

  /// What every key is stored under: `just_secure:<key>`.
  static const String prefix = 'just_secure:';

  static const _cipher = WebAesGcmCipher();
  static const _source = 'localStorage';

  final WebKeyStore _keys = WebKeyStore();
  final ValueWatchers _watchers = ValueWatchers();

  Map<String, String>? _cache;
  Future<void>? _loading;
  web.CryptoKey? _key;

  /// The end of the chain of changes; it never fails.
  Future<void> _queue = Future.value();

  StreamSubscription<web.StorageEvent>? _otherTabs;

  /// Writes, deletes and clears called and not finished, for [dispose].
  final Set<Future<void>> _changes = {};

  Future<void> _tracked(Future<void> change) {
    _changes.add(change);
    change.whenComplete(() {
      _changes.remove(change);
    }).ignore();
    return change;
  }

  static web.Storage get _local {
    try {
      return web.window.localStorage;
    } catch (e) {
      throw StorageException('localStorage is not available here.', cause: e);
    }
  }

  // --------------------------------------------------------------------------
  // JustSecureStorage
  // --------------------------------------------------------------------------

  @override
  Future<String?> read(String key) async => (await _entries())[key];

  @override
  Future<bool> containsKey(String key) async =>
      (await _entries()).containsKey(key);

  @override
  Future<Map<String, String>> readAll() async =>
      Map.unmodifiable(await _entries());

  @override
  Future<void> write(String key, String value) => _tracked(_write(key, value));

  Future<void> _write(String key, String value) async {
    await _entries();
    await _serial(() async {
      final sealed = await _seal(await _keyForWriting(), key, value);
      try {
        _local.setItem('$prefix$key', sealed);
      } on StorageException {
        rethrow;
      } catch (e) {
        // QuotaExceededError, most often.
        throw StorageException('Could not write "$key".', cause: e);
      }
      _cache?[key] = value;
    });
    _watchers.changed(key, value);
  }

  @override
  Future<void> delete(String key) => _tracked(_delete(key));

  Future<void> _delete(String key) async {
    await _entries();
    await _serial(() async {
      try {
        _local.removeItem('$prefix$key');
      } on StorageException {
        rethrow;
      } catch (e) {
        throw StorageException('Could not delete "$key".', cause: e);
      }
      _cache?.remove(key);
    });
    _watchers.changed(key, null);
  }

  /// Removes every value. Values that can't be decrypted are removed too,
  /// and a damaged key, so the next write starts over.
  @override
  Future<void> clear() => _tracked(_clear(wipe: false));

  /// Removes every value and deletes the key, so nothing written so far can
  /// be decrypted again, even from a copy. The next write makes a new key.
  Future<void> wipe() => _tracked(_clear(wipe: true));

  @override
  Stream<String?> watch(String key) {
    _listenToOtherTabs();
    return _watchers.watch(key, load: _entries, now: () => _cache?[key]);
  }

  /// Waits for the writes, deletes and clears called so far, then ends
  /// every [watch] stream, stops listening to other tabs, and lets go of the
  /// values in memory. The storage still works afterwards: the next call
  /// reads them again.
  Future<void> dispose() async {
    // What starts while waiting is waited for too.
    while (true) {
      final queue = _queue;
      final changes = [..._changes];
      await Future.wait([
        for (final change in changes) change.then((_) {}, onError: (_) {}),
        queue,
      ]);
      if (_changes.isEmpty && identical(queue, _queue)) break;
    }
    await _otherTabs?.cancel();
    _otherTabs = null;
    _watchers.closeAll();
    _cache = null;
    _loading = null;
    _key = null;
  }

  // --------------------------------------------------------------------------
  // Loading
  // --------------------------------------------------------------------------

  Future<Map<String, String>> _entries() async {
    final cache = _cache;
    if (cache != null) return cache;
    final loading = _loading ??= _load();
    try {
      await loading;
    } catch (_) {
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
    return _cache ?? await _entries();
  }

  Future<void> _load() async {
    _listenToOtherTabs();
    final local = _local;
    final stored = <String, String>{
      for (final name in _names(local))
        name.substring(prefix.length): ?local.getItem(name),
    };
    if (stored.isEmpty) {
      _cache = {};
      return;
    }
    final key = _key ??= await _keys.find();
    if (key == null) {
      throw const StorageCorruptException(
        _source,
        'holds encrypted values, but their key is missing from IndexedDB.',
      );
    }
    final entries = <String, String>{};
    final unreadable = <String>[];
    final oldFormat = <String>[];
    for (final MapEntry(key: name, value: raw) in stored.entries) {
      try {
        final (:value, :version) = await _open(key, name, raw);
        entries[name] = value;
        if (version < SealedValue.current) oldFormat.add(name);
      } on FormatException {
        unreadable.add(name);
      } on StorageException {
        unreadable.add(name);
      }
    }
    if (unreadable.isNotEmpty) {
      throw StorageCorruptException(
        _source,
        unreadable.length == stored.length
            ? 'none of its encrypted values can be decrypted with the key '
                  'in IndexedDB: the key is not theirs, or they were changed.'
            : 'some encrypted values can\'t be decrypted: they were changed, '
                  'or moved from another key.',
        keys: unreadable,
      );
    }
    _cache = entries;
    if (oldFormat.isNotEmpty) {
      // Written before 2.0.0: seal them again, bound to their keys.
      unawaited(
        _serial(() async {
          for (final name in oldFormat) {
            final value = _cache?[name];
            if (value == null) continue;
            _local.setItem('$prefix$name', await _seal(key, name, value));
          }
        }).catchError((Object _) {}),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  /// Runs [change] after the changes before it, so writes land in order.
  Future<T> _serial<T>(Future<T> Function() change) {
    final result = _queue.then((_) => change());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<web.CryptoKey> _keyForWriting() async =>
      _key ??= await _keys.findOrCreate();

  Future<void> _clear({required bool wipe}) async {
    var unreadable = false;
    try {
      await _entries();
    } on StorageCorruptException {
      unreadable = true;
    }
    final cleared = <String>{};
    await _serial(() async {
      try {
        final local = _local;
        for (final name in _names(local)) {
          local.removeItem(name);
          cleared.add(name.substring(prefix.length));
        }
      } on StorageException {
        rethrow;
      } catch (e) {
        throw StorageException('Could not clear the storage.', cause: e);
      }
      cleared.addAll(_cache?.keys ?? const <String>[]);
      _cache = {};
      _loading = null;
      if (wipe) {
        _key = null;
        await _keys.delete();
      } else if (unreadable) {
        // Keep a working key: other tabs may hold it. A damaged one goes.
        _key = null;
        _keys.removeDamagedRawKey();
      }
    });
    for (final key in {...cleared, ..._watchers.keys}) {
      _watchers.changed(key, null);
    }
  }

  static Future<String> _seal(
    web.CryptoKey key,
    String name,
    String value,
  ) async {
    final sealed = await _cipher.seal(
      key,
      Uint8List.fromList(utf8.encode(value)),
      SealedValue.aadFor(name, SealedValue.current),
    );
    return jsonEncode({
      'v': SealedValue.current,
      ...SealedValue(sealed.nonce, sealed.ciphertext).toJson(),
    });
  }

  /// Decrypts [raw], the stored form of [name]'s value. Throws a
  /// [FormatException] or a [StorageException] when it can't.
  static Future<({String value, int version})> _open(
    web.CryptoKey key,
    String name,
    String raw,
  ) async {
    final json = jsonDecode(raw);
    final v = json is Map ? json['v'] : null;
    final version = v is int ? v : 1;
    if (version != 1 && version != SealedValue.current) {
      throw FormatException('Format $version is not one this reads.');
    }
    final sealed = SealedValue.fromJson(json);
    final plain = await _cipher.open(
      key,
      sealed.nonce,
      sealed.ciphertext,
      SealedValue.aadFor(name, version),
    );
    return (value: utf8.decode(plain), version: version);
  }

  static List<String> _names(web.Storage local) => [
    for (var i = 0; i < local.length; i++)
      if (local.key(i) case final name? when name.startsWith(prefix)) name,
  ];

  // --------------------------------------------------------------------------
  // Other tabs
  // --------------------------------------------------------------------------

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
      // Cleared outright: read what is left, key included, again.
      _key = null;
      unawaited(_serial(_reload));
      return;
    }
    if (name == WebKeyStore.epochEntry) {
      // The key was made or deleted there: find it again.
      _key = null;
      return;
    }
    if (!name.startsWith(prefix)) return;
    final key = name.substring(prefix.length);
    final raw = event.newValue;
    unawaited(
      _serial(() async {
        final cache = _cache;
        if (cache == null) return; // Not read yet: the first read sees it.
        if (raw == null) {
          cache.remove(key);
          _watchers.changed(key, null);
          return;
        }
        try {
          final cryptoKey = _key ??= await _keys.find();
          if (cryptoKey == null) return;
          final (:value, version: _) = await _open(cryptoKey, key, raw);
          cache[key] = value;
          _watchers.changed(key, value);
        } catch (_) {
          // Not readable here: keep this tab's copy.
        }
      }),
    );
  }

  Future<void> _reload() async {
    final before = _cache;
    _cache = null;
    _loading = null;
    try {
      await _entries();
    } catch (_) {
      // Reported to the next caller, which reads again.
    }
    for (final key in {...?before?.keys, ..._watchers.keys}) {
      _watchers.changed(key, _cache?[key]);
    }
  }
}
