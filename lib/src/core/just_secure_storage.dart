import 'just_key_value_storage.dart';
import 'just_standard_storage.dart';

/// Persistent key-value storage whose values are encrypted where they are
/// kept: tokens, credentials, personal data.
///
/// Every value is encrypted on its own with AES-256-GCM, which also detects
/// any change made to it outside the storage. Read the package README's
/// *Security model* for what that protects against and what it doesn't. Use
/// [JustStandardStorage] for values that need no secrecy; it is faster.
///
/// Get one from the factory, which picks the platform's implementation:
///
/// ```dart
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// await secure.write('access_token', token);
/// ```
abstract class JustSecureStorage extends JustKeyValueStorage {
  /// Constructor for subclasses.
  const JustSecureStorage();
}
