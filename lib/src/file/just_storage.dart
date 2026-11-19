import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/core.dart';
import 'encrypted_file_storage.dart';
import 'file_storage.dart';

/// Opens the storages, on native platforms.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
///
/// Every call for one folder hands back the **same** instance. A storage
/// keeps its whole file in memory and writes it back whole, so two
/// instances over one folder would each write over the other's keys.
/// Because the instance is shared, disposing it affects everyone using it.
///
/// Without a folder, the app's support directory
/// (`getApplicationSupportDirectory()`) is used, which needs the Flutter
/// binding: call `WidgetsFlutterBinding.ensureInitialized()` first when you
/// open a storage before `runApp`.
abstract final class JustStorage {
  static final Map<String, FileStorage> _standard = {};
  static final Map<String, EncryptedFileStorage> _encrypted = {};

  /// The [FileStorage] for [directory] (default: the app's support
  /// directory): plain JSON in `just_storage.json`.
  ///
  /// Pass a folder of your own in tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final storage = await JustStorage.standard(dir);
  /// ```
  static Future<JustStandardStorage> standard([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _standard.putIfAbsent(_idOf(dir), () => FileStorage(dir));
  }

  /// The [EncryptedFileStorage] for [directory] (default: the app's support
  /// directory): AES-256-GCM in `just_secure_storage.enc`, with its key in
  /// `.storage.key`.
  ///
  /// Pass a folder of your own in tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final secure = await JustStorage.encrypted(dir);
  /// ```
  static Future<JustSecureStorage> encrypted([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _encrypted.putIfAbsent(_idOf(dir), () => EncryptedFileStorage(dir));
  }

  /// One name for every spelling of [dir]: relative, with `..` or a
  /// trailing separator, or (on Windows, whose file names ignore case) in
  /// another case.
  static String _idOf(Directory dir) {
    var path = dir.absolute.uri.normalizePath().toFilePath();
    final separator = Platform.pathSeparator;
    while (path.length > 1 && path.endsWith(separator)) {
      path = path.substring(0, path.length - 1);
    }
    return Platform.isWindows ? path.toLowerCase() : path;
  }
}
