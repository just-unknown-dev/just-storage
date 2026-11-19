import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;
import 'package:web/web.dart' as web;

import '../core/core.dart';
import 'web_aes_gcm_cipher.dart';

/// Where `WebSecureStorage` keeps its key: a non-extractable `CryptoKey` in
/// IndexedDB (database `just_storage`, store `keys`).
///
/// A script on the page can use the key, but can't read its bytes, so it
/// can't send them anywhere or decrypt a copy of the values elsewhere.
/// Before 2.0.0 the key was kept raw, in `localStorage`; such a key is moved
/// to IndexedDB the first time it is found, and its raw copy removed. Where
/// IndexedDB is unavailable, a key is still kept raw in `localStorage`.
@internal
final class WebKeyStore {
  static const String _database = 'just_storage';
  static const String _objectStore = 'keys';
  static const String _keyId = 'secure_storage';

  /// The `localStorage` entry of a raw key: where versions before 2.0.0
  /// kept it, and where it is kept where IndexedDB is unavailable.
  static const String rawKeyEntry = 'just_secure_key:__master__';

  /// The `localStorage` entry that changes whenever the key is made or
  /// deleted, so other tabs know to find it again.
  static const String epochEntry = 'just_secure_key:epoch';

  /// The key, or `null` when there is none.
  ///
  /// Throws a [StorageCorruptException] when a raw key in `localStorage`
  /// isn't a key.
  Future<web.CryptoKey?> find() async {
    final raw = _rawKey();
    web.CryptoKey? stored;
    try {
      stored = await _get();
    } catch (_) {
      // No IndexedDB here: a raw key is all there can be.
      return raw == null ? null : WebAesGcmCipher.importRawKey(raw);
    }
    if (raw == null) return stored;
    final fromRaw = await WebAesGcmCipher.importRawKey(raw);
    if (stored == null) {
      // A key from before 2.0.0: move it.
      final kept = await _add(fromRaw);
      if (await _same(kept, fromRaw)) _removeRaw();
      return kept;
    }
    // Both: a move that stopped before it removed the raw copy.
    if (await _same(stored, fromRaw)) _removeRaw();
    return stored;
  }

  /// The key, made now if there is none.
  Future<web.CryptoKey> findOrCreate() async {
    final found = await find();
    if (found != null) return found;
    web.CryptoKey kept;
    try {
      kept = await _add(await WebAesGcmCipher.generateKey());
    } catch (_) {
      // No IndexedDB here: keep the key raw in localStorage.
      final raw = WebAesGcmCipher.randomBytes(WebAesGcmCipher.keyLength);
      _local.setItem(rawKeyEntry, base64.encode(raw));
      kept = await WebAesGcmCipher.importRawKey(raw);
    }
    _bumpEpoch();
    return kept;
  }

  /// Deletes the key, from IndexedDB and `localStorage`. Every value sealed
  /// with it can no longer be read.
  Future<void> delete() async {
    try {
      await _delete();
    } catch (_) {
      // No IndexedDB here: nothing kept there.
    }
    _removeRaw();
    _bumpEpoch();
  }

  /// Removes a raw key that isn't a key, so a new one can be made.
  void removeDamagedRawKey() {
    try {
      _rawKey();
    } on StorageCorruptException {
      _removeRaw();
    }
  }

  static web.Storage get _local => web.window.localStorage;

  Uint8List? _rawKey() {
    final stored = _local.getItem(rawKeyEntry);
    if (stored == null) return null;
    Uint8List bytes;
    try {
      bytes = base64.decode(stored);
    } on FormatException catch (e) {
      throw StorageCorruptException(
        'localStorage',
        'the key in "$rawKeyEntry" is not base64.',
        cause: e,
      );
    }
    if (bytes.length != WebAesGcmCipher.keyLength) {
      throw StorageCorruptException(
        'localStorage',
        'the key in "$rawKeyEntry" is ${bytes.length} bytes, not '
            '${WebAesGcmCipher.keyLength}.',
      );
    }
    return bytes;
  }

  void _removeRaw() => _local.removeItem(rawKeyEntry);

  void _bumpEpoch() =>
      _local.setItem(epochEntry, base64.encode(WebAesGcmCipher.randomBytes(8)));

  /// Whether [a] and [b] are the same key: what one seals, the other opens.
  static Future<bool> _same(web.CryptoKey a, web.CryptoKey b) async {
    if (identical(a, b)) return true;
    const cipher = WebAesGcmCipher();
    final probe = WebAesGcmCipher.randomBytes(16);
    final sealed = await cipher.seal(a, probe, Uint8List(0));
    try {
      await cipher.open(b, sealed.nonce, sealed.ciphertext, Uint8List(0));
      return true;
    } on StorageException {
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // IndexedDB
  // --------------------------------------------------------------------------

  static Future<web.CryptoKey?> _get() => _use((db) async {
    final tx = db.transaction(_objectStore.toJS, 'readonly');
    final result = await _request(
      tx.objectStore(_objectStore).get(_keyId.toJS),
    );
    if (result == null || result.isUndefinedOrNull) return null;
    return result as web.CryptoKey;
  });

  /// Adds [key] unless a key is there already; returns the key kept.
  static Future<web.CryptoKey> _add(web.CryptoKey key) async {
    final added = await _use((db) async {
      final tx = db.transaction(_objectStore.toJS, 'readwrite');
      final done = _transaction(tx)..ignore();
      try {
        await _request(tx.objectStore(_objectStore).add(key, _keyId.toJS));
      } on _IdbError catch (e) {
        if (e.name != 'ConstraintError') rethrow;
        // Another tab added one first.
        await done;
        return false;
      }
      await done;
      return true;
    });
    if (added) return key;
    return await _get() ??
        (throw const StorageException('The key vanished from IndexedDB.'));
  }

  static Future<void> _delete() => _use((db) async {
    final tx = db.transaction(_objectStore.toJS, 'readwrite');
    final done = _transaction(tx)..ignore();
    await _request(tx.objectStore(_objectStore).delete(_keyId.toJS));
    await done;
  });

  static Future<T> _use<T>(Future<T> Function(web.IDBDatabase db) body) async {
    final db = await _open();
    try {
      return await body(db);
    } finally {
      db.close();
    }
  }

  static Future<web.IDBDatabase> _open() {
    final opened = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request;
    try {
      request = web.window.indexedDB.open(_database, 1);
    } catch (e) {
      return Future.error(_IdbError('UnknownError', '$e'));
    }
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_objectStore)) {
        db.createObjectStore(_objectStore);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      opened.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event event) {
      event.preventDefault();
      final error = request.error;
      opened.completeError(
        _IdbError(error?.name ?? 'UnknownError', error?.message ?? ''),
      );
    }).toJS;
    return opened.future;
  }

  static Future<JSAny?> _request(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      done.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event event) {
      // Handled here: the transaction carries on.
      event.preventDefault();
      final error = request.error;
      done.completeError(
        _IdbError(error?.name ?? 'UnknownError', error?.message ?? ''),
      );
    }).toJS;
    return done.future;
  }

  static Future<void> _transaction(web.IDBTransaction tx) {
    final done = Completer<void>();
    void fail(web.Event _) {
      if (done.isCompleted) return;
      final error = tx.error;
      done.completeError(
        _IdbError(error?.name ?? 'AbortError', error?.message ?? ''),
      );
    }

    tx.oncomplete = ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    tx.onerror = fail.toJS;
    tx.onabort = fail.toJS;
    return done.future;
  }
}

final class _IdbError implements Exception {
  _IdbError(this.name, this.message);

  final String name;
  final String message;

  @override
  String toString() => 'IndexedDB $name: $message';
}
