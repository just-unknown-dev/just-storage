import 'just_secure_storage.dart';
import 'just_standard_storage.dart';

/// Thrown by a [JustStandardStorage] or [JustSecureStorage] when an
/// operation fails: the disk is full, a file can't be read or written, a
/// value isn't the JSON its reader expects.
///
/// Wrap it in your own domain exceptions if you need to tell callers further
/// up about a storage failure.
class StorageException implements Exception {
  /// Creates a [StorageException] with a human-readable [message] and an
  /// optional underlying [cause].
  const StorageException(this.message, {this.cause});

  /// Human-readable description of what went wrong.
  final String message;

  /// The underlying exception or error that triggered this [StorageException],
  /// if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'StorageException: $message (caused by: $cause)';
    }
    return 'StorageException: $message';
  }
}

/// Thrown when what a storage keeps can't be read back: its file isn't the
/// JSON it writes, an encrypted value fails its integrity check, or the key
/// that decrypts the values is missing or damaged.
///
/// The storage leaves what it found untouched, so nothing is lost by
/// accident: every read and write throws this until the cause is gone.
/// `clear()` is the way to start over: it works on a storage that can't be
/// read, and replaces what is there with an empty store.
///
/// ```dart
/// try {
///   token = await secure.read('access_token');
/// } on StorageCorruptException {
///   await secure.clear(); // the user signs in again
/// }
/// ```
class StorageCorruptException extends StorageException {
  /// Creates a [StorageCorruptException] about [source] — a file's path, or
  /// where on the web the values are kept.
  const StorageCorruptException(
    this.source,
    super.message, {
    this.keys = const [],
    super.cause,
  });

  /// What can't be read: a file's path, or `localStorage` on the web.
  final String source;

  /// The keys whose values can't be read, when it is only some of them;
  /// empty when the whole store can't be.
  final List<String> keys;

  @override
  String toString() {
    final which = keys.isEmpty ? '' : ' (keys: ${keys.join(', ')})';
    final why = cause == null ? '' : ' (caused by: $cause)';
    return 'StorageCorruptException: $source: $message$which$why';
  }
}
