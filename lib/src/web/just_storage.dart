import '../core/core.dart';
import 'web_secure_storage.dart';
import 'web_storage.dart';

/// Opens the storages, on the web.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
///
/// Every call hands back the **same** instance: a second [WebSecureStorage]
/// would keep its own copy of the values and miss this one's writes.
/// Because the instance is shared, disposing it affects everyone using it.
abstract final class JustStorage {
  static WebStorage? _standard;
  static WebSecureStorage? _encrypted;

  /// The page's [WebStorage]: `localStorage`, keys prefixed `just_storage:`.
  ///
  /// [directory] is there so calls compile on every platform; the web has
  /// no folders, and it is ignored.
  static Future<JustStandardStorage> standard([Object? directory]) async =>
      _standard ??= WebStorage();

  /// The page's [WebSecureStorage]: AES-256-GCM values in `localStorage`,
  /// keys prefixed `just_secure:`, the key in IndexedDB.
  ///
  /// [directory] is there so calls compile on every platform; the web has
  /// no folders, and it is ignored.
  static Future<JustSecureStorage> encrypted([Object? directory]) async =>
      _encrypted ??= WebSecureStorage();
}
