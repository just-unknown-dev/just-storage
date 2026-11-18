import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'implementations/encrypted_file_storage.dart';
import 'implementations/file_storage.dart';
import 'just_secure_storage.dart';
import 'just_standard_storage.dart';

/// Convenience factory for creating just_storage instances.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage   secure  = await JustStorage.encrypted();
/// ```
///
/// Each call with the same directory returns the **same** instance. An
/// instance keeps the whole store in memory and rewrites its file on every
/// write, so two instances over one directory would silently overwrite each
/// other's keys. Sharing one instance per directory keeps every caller's
/// writes. Because the instance is shared, calling `dispose()` on it affects
/// every holder.
///
/// Register in a DI container (e.g. `just_di`):
/// ```dart
/// final secure = await JustStorage.encrypted();
/// JustDi.registerLazySingleton<JustSecureStorage>(() => secure);
/// ```
abstract final class JustStorage {
  JustStorage._();

  static final Map<String, FileStorage> _standardInstances = {};
  static final Map<String, EncryptedFileStorage> _encryptedInstances = {};

  /// Returns the [FileStorage] backed by the platform's application support
  /// directory.  Values are stored as plain JSON.
  ///
  /// Pass [directory] to override the resolved path — useful in unit tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final storage = await JustStorage.standard(dir);
  /// ```
  ///
  /// Repeated calls for the same directory return the same instance.
  static Future<JustStandardStorage> standard([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _standardInstances.putIfAbsent(
      _instanceKey(dir),
      () => FileStorage(dir),
    );
  }

  /// Returns the [EncryptedFileStorage] backed by the platform's application
  /// support directory.  Values are encrypted with AES-256-GCM.
  ///
  /// Pass [directory] to override the resolved path — useful in unit tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final secure = await JustStorage.encrypted(dir);
  /// ```
  ///
  /// Repeated calls for the same directory return the same instance.
  static Future<JustSecureStorage> encrypted([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _encryptedInstances.putIfAbsent(
      _instanceKey(dir),
      () => EncryptedFileStorage(dir),
    );
  }

  /// Normalises [dir] so that different spellings of one directory
  /// (relative, `..` segments, letter case on Windows) share an instance.
  static String _instanceKey(Directory dir) {
    final path = dir.absolute.uri.normalizePath().toFilePath();
    return Platform.isWindows ? path.toLowerCase() : path;
  }
}
