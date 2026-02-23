import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../just_secure_storage.dart';
import '../models/storage_exception.dart';
import '../security/aes_gcm_cipher.dart';
import '../security/storage_key_manager.dart';

/// [JustSecureStorage] implementation that encrypts every value with AES-256-GCM.
/// No third-party storage packages are used.
///
/// ### On-disk format
/// A single JSON file `<directory>/just_secure_storage.enc` with the shape:
/// ```json
/// {
///   "access_token": { "n": "<base64 nonce>", "ct": "<base64 ctag>" },
///   "refresh_token": { "n": "<base64 nonce>", "ct": "<base64 ctag>" }
/// }
/// ```
/// Each value is **independently** encrypted with a fresh random 12-byte
/// nonce, so a nonce collision for one entry never compromises another.
/// The `"ct"` field is `ciphertext || 16-byte GCM auth tag`; any bit-flip is
/// detected and rejected before plaintext is returned.
///
/// ### Master key
/// Managed by [StorageKeyManager].  The key lives at
/// `<directory>/.storage.key` (owner-read-only on POSIX).
///
/// ### Atomicity
/// Mutations are written to `<name>.tmp` then renamed over the target —
/// an atomic OS-level swap on all supported platforms.
///
/// Obtain an instance via the factory:
/// ```dart
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
class EncryptedFileStorage implements JustSecureStorage {
  EncryptedFileStorage(this._directory)
      : _keyManager = StorageKeyManager(_directory),
        _cipher = AesGcmCipher();

  final Directory _directory;
  final StorageKeyManager _keyManager;
  final AesGcmCipher _cipher;

  static const String _fileName = 'just_secure_storage.enc';

  /// Plaintext in-memory cache: `key → plaintext value`.
  Map<String, String>? _cache;
  Uint8List? _masterKey;
  Future<void>? _initFuture;
  final Map<String, StreamController<String?>> _controllers = {};

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  File get _dataFile =>
      File('${_directory.path}${Platform.pathSeparator}$_fileName');

  File get _tmpFile =>
      File('${_directory.path}${Platform.pathSeparator}$_fileName.tmp');

  /// Guards against concurrent initialisation: all callers await the same
  /// Future so `_doInit` body runs exactly once.
  Future<void> _init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    _masterKey ??= await _keyManager.loadOrCreate();

    final file = _dataFile;
    if (!await file.exists()) {
      _cache = {};
      return;
    }

    try {
      final raw = await file.readAsString();
      final outer = jsonDecode(raw);
      if (outer is! Map) {
        _cache = {};
        return;
      }

      final result = <String, String>{};
      for (final entry in outer.entries) {
        final k = entry.key as String;
        final v = entry.value;
        if (v is! Map) continue;

        final nonce = base64.decode(v['n'] as String);
        final ct = base64.decode(v['ct'] as String);
        final plainBytes = _cipher.decrypt(
          _masterKey!,
          Uint8List.fromList(nonce),
          Uint8List.fromList(ct),
        );
        result[k] = utf8.decode(plainBytes);
      }
      _cache = result;
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException(
        'Failed to load encrypted storage file.',
        cause: e,
      );
    }
  }

  Future<void> _flush() async {
    await _directory.create(recursive: true);
    _masterKey ??= await _keyManager.loadOrCreate();

    final outer = <String, Map<String, String>>{};
    for (final entry in _cache!.entries) {
      final nonce = AesGcmCipher.randomNonce();
      final ct = _cipher.encrypt(
        _masterKey!,
        nonce,
        Uint8List.fromList(utf8.encode(entry.value)),
      );
      outer[entry.key] = {
        'n': base64.encode(nonce),
        'ct': base64.encode(ct),
      };
    }

    final tmp = _tmpFile;
    await tmp.writeAsString(jsonEncode(outer), flush: true);
    await tmp.rename(_dataFile.path);
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
  // JustStorage
  // --------------------------------------------------------------------------

  @override
  Future<String?> read(String key) async {
    await _init();
    return _cache![key];
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _init();
      _cache![key] = value;
      await _flush();
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
      await _init();
      _cache!.remove(key);
      await _flush();
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
      await _init();
      final keys = List<String>.from(_cache!.keys);
      _cache!.clear();
      await _flush();
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
    await _init();
    return _cache!.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    await _init();
    return Map.unmodifiable(_cache!);
  }

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    try {
      await _init();
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
    // Events that arrive while the snapshot is still being prepared are
    // buffered and replayed immediately after the snapshot is emitted,
    // preserving causal order.
    final buffered = <String?>[];
    bool snapshotEmitted = false;

    late StreamController<String?> sc;
    late StreamSubscription<String?> innerSub;

    sc = StreamController<String?>(
      sync: true,
      onListen: () async {
        innerSub = _controllerFor(key).stream.listen((value) {
          if (snapshotEmitted) {
            sc.add(value);
          } else {
            buffered.add(value);
          }
        });

        try {
          await _init();
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

  /// Disposes all open stream controllers and releases the in-memory cache.
  /// If [destroyKey] is `true`, also deletes the master key file — **all
  /// encrypted data will become permanently unreadable.**  Only use this for
  /// a full data-wipe.
  Future<void> dispose({bool destroyKey = false}) async {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
    _cache = null;
    _masterKey = null;
    if (destroyKey) {
      await _keyManager.destroy();
    }
  }
}
