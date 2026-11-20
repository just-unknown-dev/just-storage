import 'just_key_value_storage.dart';
import 'just_secure_storage.dart';

/// Persistent key-value storage for values that need no secrecy: settings,
/// preferences, game state.
///
/// On native platforms the values are kept as plain JSON in one file; on the
/// web, in the browser's `localStorage`. Use [JustSecureStorage] for tokens,
/// credentials and anything else that must not be readable on disk.
///
/// Get one from the factory, which picks the platform's implementation:
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// await storage.write('theme', 'dark');
/// ```
abstract class JustStandardStorage extends JustKeyValueStorage {
  /// Constructor for subclasses.
  const JustStandardStorage();
}
