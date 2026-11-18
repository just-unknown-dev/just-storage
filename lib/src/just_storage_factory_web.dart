import 'implementations/web_secure_storage.dart';
import 'implementations/web_storage.dart';
import 'just_secure_storage.dart';
import 'just_standard_storage.dart';

/// Convenience factory for creating just_storage instances on the web platform.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage   secure  = await JustStorage.encrypted();
/// ```
///
/// Each factory returns the **same** instance on every call, matching the
/// native factory's one-instance-per-directory behaviour. A second
/// [WebSecureStorage] would keep its own decrypted cache and miss the other
/// instance's writes, and `watch` streams only see writes made through the
/// instance they were opened on.
abstract final class JustStorage {
  JustStorage._();

  static WebStorage? _standard;
  static WebSecureStorage? _encrypted;

  /// Returns the [WebStorage] instance backed by the browser's `localStorage`.
  /// Values are stored as plain strings under prefixed keys.
  ///
  /// The [directory] parameter is accepted for API compatibility with the
  /// native factory but is ignored on web.
  static Future<JustStandardStorage> standard([dynamic directory]) async {
    return _standard ??= WebStorage();
  }

  /// Returns the [WebSecureStorage] instance backed by the browser's
  /// `localStorage` with AES-256-GCM encryption.
  ///
  /// The [directory] parameter is accepted for API compatibility with the
  /// native factory but is ignored on web.
  static Future<JustSecureStorage> encrypted([dynamic directory]) async {
    return _encrypted ??= WebSecureStorage();
  }
}
