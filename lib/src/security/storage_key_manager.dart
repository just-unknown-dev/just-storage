import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/storage_exception.dart';

/// Manages the 256-bit master encryption key used by [EncryptedFileStorage].
///
/// On first use a cryptographically-random key is generated and written to a
/// hidden dot-file inside the app's private sandbox.  On subsequent uses the
/// key is loaded from that file.
///
/// **Security note:** this key is only as secure as the file system sandbox
/// that protects it.  On Android (API 29+) and iOS the app's data directory is
/// inaccessible to other apps without root.  On desktops the file permissions
/// are narrowed to owner-read-only (`0600`) wherever `dart:io` supports it.
///
/// Inject a [Directory] for full testability:
/// ```dart
/// final km = StorageKeyManager(await getApplicationSupportDirectory());
/// final key = await km.loadOrCreate();
/// ```
class StorageKeyManager {
  StorageKeyManager(this._directory);

  final Directory _directory;

  static const int _keyLength = 32; // 256-bit AES key
  static const String _keyFileName = '.storage.key';

  File get _keyFile =>
      File('${_directory.path}${Platform.pathSeparator}$_keyFileName');

  /// Returns the master key, generating and persisting it on first call.
  ///
  /// Throws [StorageException] if the stored key file is corrupt (wrong size).
  Future<Uint8List> loadOrCreate() async {
    final file = _keyFile;

    if (await file.exists()) {
      return _loadKey(file);
    }

    return _generateAndStore(file);
  }

  Future<Uint8List> _loadKey(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length != _keyLength) {
        throw StorageException(
          'Master key file is corrupt: expected $_keyLength bytes, '
          'got ${bytes.length}.',
        );
      }
      return Uint8List.fromList(bytes);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to read master key file.', cause: e);
    }
  }

  Future<Uint8List> _generateAndStore(File file) async {
    final rng = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => rng.nextInt(256)),
    );

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(key, flush: true);

      // Narrow permissions to owner-only on POSIX systems.
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', file.path]);
      }
    } catch (e) {
      throw StorageException('Failed to persist master key file.', cause: e);
    }

    return key;
  }

  /// Deletes the key file.  **All encrypted data will become permanently
  /// unreadable.**  Used only for full data wipe scenarios.
  Future<void> destroy() async {
    final file = _keyFile;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
