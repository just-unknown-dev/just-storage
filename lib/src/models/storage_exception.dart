/// Thrown by [JustStandardStorage] and [JustSecureStorage] implementations
/// when a storage operation fails unexpectedly.
///
/// Wrap this in your own domain exceptions if you need to communicate storage
/// failures further up the call stack.
class StorageException implements Exception {
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
