import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../just_secure_storage.dart';
import '../models/storage_exception.dart';
import '../security/aes_gcm_cipher.dart';

/// [JustSecureStorage] implementation for web, backed by the browser's
/// `window.localStorage` with AES-256-GCM authenticated encryption.
///
/// The master key is generated on first use and stored in `localStorage`
/// under a reserved key.  All data entries are stored encrypted under keys
/// prefixed with `just_secure:`.
///
/// **Note:** Because `localStorage` is accessible to all scripts running on
/// the same origin, the security guarantee is equivalent to in-memory
/// protection rather than OS-level sandboxing.  Prefer a server-side solution
/// for highly sensitive data in web applications.
///
/// Obtain an instance via the factory:
/// ```dart
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
class WebSecureStorage implements JustSecureStorage {
  static const String _dataPrefix = 'just_secure:';
  static const String _masterKeyEntry = 'just_secure_key:__master__';
  static const int _keyLength = 32; // 256-bit

  final AesGcmCipher _cipher = AesGcmCipher();

  Uint8List? _masterKey;
  Map<String, String>? _cache;

  final Map<String, StreamController<String?>> _controllers = {};

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  String _prefixed(String key) => '$_dataPrefix$key';

  Uint8List _loadOrCreateKey() {
    final stored = web.window.localStorage.getItem(_masterKeyEntry);
    if (stored != null) {
      final bytes = base64.decode(stored);
      if (bytes.length != _keyLength) {
        throw StorageException(
          'Stored web master key is corrupt: expected $_keyLength bytes, '
          'got ${bytes.length}.',
        );
      }
      return Uint8List.fromList(bytes);
    }

    final rng = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => rng.nextInt(256)),
    );
    web.window.localStorage.setItem(_masterKeyEntry, base64.encode(key));
    return key;
  }

  void _ensureInit() {
    if (_masterKey != null && _cache != null) return;

    _masterKey = _loadOrCreateKey();
    _cache = _loadCache();
  }

  Map<String, String> _loadCache() {
    final result = <String, String>{};
    final ls = web.window.localStorage;
    for (var i = 0; i < ls.length; i++) {
      final k = ls.key(i);
      if (k == null || !k.startsWith(_dataPrefix)) continue;
      final shortKey = k.substring(_dataPrefix.length);
      final rawValue = ls.getItem(k);
      if (rawValue == null) continue;
      try {
        final outer = jsonDecode(rawValue);
        if (outer is! Map) continue;

        final nonce = base64.decode(outer['n'] as String);
        final ct = base64.decode(outer['ct'] as String);
        final plainBytes = _cipher.decrypt(
          _masterKey!,
          Uint8List.fromList(nonce),
          Uint8List.fromList(ct),
        );
        result[shortKey] = utf8.decode(plainBytes);
      } catch (_) {
        // Skip any corrupted entry.
      }
    }
    return result;
  }

  void _flushEntry(String key, String plaintext) {
    final nonce = AesGcmCipher.randomNonce();
    final ct = _cipher.encrypt(
      _masterKey!,
      nonce,
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    final payload = jsonEncode({
      'n': base64.encode(nonce),
      'ct': base64.encode(ct),
    });
    web.window.localStorage.setItem(_prefixed(key), payload);
  }

  StreamController<String?> _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => StreamController<String?>.broadcast(sync: true),
    );
  }

  void _emit(String key, String? value) {
    if (_controllers.containsKey(key)) {
      _controllers[key]!.add(value);
    }
  }

  // --------------------------------------------------------------------------
  // JustSecureStorage
  // --------------------------------------------------------------------------

  @override
  Future<String?> read(String key) async {
    _ensureInit();
    return _cache![key];
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      _ensureInit();
      _cache![key] = value;
      _flushEntry(key, value);
      _emit(key, value);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to write secure key "$key".', cause: e);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      _ensureInit();
      _cache!.remove(key);
      web.window.localStorage.removeItem(_prefixed(key));
      _emit(key, null);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to delete secure key "$key".', cause: e);
    }
  }

  @override
  Future<void> clear() async {
    try {
      _ensureInit();
      final keys = List<String>.from(_cache!.keys);
      _cache!.clear();
      final ls = web.window.localStorage;
      final lsKeysToRemove = <String>[];
      for (var i = 0; i < ls.length; i++) {
        final k = ls.key(i);
        if (k != null && k.startsWith(_dataPrefix)) lsKeysToRemove.add(k);
      }
      for (final k in lsKeysToRemove) {
        ls.removeItem(k);
      }
      for (final k in keys) {
        _emit(k, null);
      }
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to clear all keys.', cause: e);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    _ensureInit();
    return _cache!.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    _ensureInit();
    return Map.unmodifiable(_cache!);
  }

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    try {
      _ensureInit();
      final raw = _cache![key];
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw StorageException(
          'Stored value for secure key "$key" is not a JSON object.',
        );
      }
      return fromJson(decoded);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        'Failed to read JSON for secure key "$key".',
        cause: e,
      );
    }
  }

  @override
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) async {
    try {
      final encoded = jsonEncode(toJson(value));
      await write(key, encoded);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        'Failed to write JSON for secure key "$key".',
        cause: e,
      );
    }
  }

  @override
  Stream<String?> watch(String key) {
    final buffered = <String?>[];
    bool snapshotEmitted = false;

    late StreamController<String?> sc;
    late StreamSubscription<String?> innerSub;

    sc = StreamController<String?>(
      sync: true,
      onListen: () {
        innerSub = _controllerFor(key).stream.listen((value) {
          if (snapshotEmitted) {
            sc.add(value);
          } else {
            buffered.add(value);
          }
        });

        try {
          _ensureInit();
          if (!sc.isClosed) {
            sc.add(_cache![key]);
            snapshotEmitted = true;
            for (final v in buffered) {
              sc.add(v);
            }
            buffered.clear();
          }
        } catch (e) {
          if (!sc.isClosed) sc.addError(e);
        }
      },
      onCancel: () => innerSub.cancel(),
    );

    return sc.stream;
  }

  /// Disposes all open stream controllers.
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
    _cache = null;
    _masterKey = null;
  }
}
