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
/// Register in a DI container (e.g. `get_it`):
/// ```dart
/// sl.registerLazySingleton<JustStandardStorage>(() => await JustStorage.standard());
/// sl.registerLazySingleton<JustSecureStorage>(()   => await JustStorage.encrypted());
/// ```
abstract final class JustStorage {
  JustStorage._();

  /// Returns a [FileStorage] instance backed by the platform's application
  /// support directory.  Values are stored as plain JSON.
  ///
  /// Pass [directory] to override the resolved path — useful in unit tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final storage = await JustStorage.standard(dir);
  /// ```
  static Future<JustStandardStorage> standard([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return FileStorage(dir);
  }

  /// Returns an [EncryptedFileStorage] instance backed by the platform's
  /// application support directory.  Values are encrypted with AES-256-GCM.
  ///
  /// Pass [directory] to override the resolved path — useful in unit tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final secure = await JustStorage.encrypted(dir);
  /// ```
  static Future<JustSecureStorage> encrypted([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return EncryptedFileStorage(dir);
  }
}
