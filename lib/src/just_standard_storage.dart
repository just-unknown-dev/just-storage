/// Interface for non-sensitive, persistent key-value storage.
///
/// The default implementation is [FileStorage], which persists data as an
/// atomic plain-JSON file using only `dart:io`.
///
/// Use [JustStorage.standard] to obtain an instance — no `path_provider`
/// import required in your app:
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// ```
///
/// Register in a DI container (e.g. `get_it`):
/// ```dart
/// sl.registerLazySingleton<JustStandardStorage>(
///   () => await JustStorage.standard(),
/// );
/// ```
abstract class JustStandardStorage {
  /// Default constructor for subclasses.
  const JustStandardStorage();

  /// Returns the raw string stored under [key], or `null` if absent.
  Future<String?> read(String key);

  /// Persists [value] under [key], overwriting any existing entry.
  Future<void> write(String key, String value);

  /// Removes the entry for [key]. No-op if the key does not exist.
  Future<void> delete(String key);

  /// Removes **all** entries managed by this storage instance.
  Future<void> clear();

  /// Returns `true` if an entry for [key] exists (even if the value is empty).
  Future<bool> containsKey(String key);

  /// Returns all key-value pairs currently in the store as an unmodifiable map.
  Future<Map<String, String>> readAll();

  // --------------------------------------------------------------------------
  // Typed JSON helpers
  // --------------------------------------------------------------------------

  /// Reads the stored JSON string for [key] and deserialises it using
  /// [fromJson].  Returns `null` if the key is absent or the stored value
  /// cannot be parsed.
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  );

  /// Serialises [value] to JSON using [toJson] and persists it under [key].
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  );

  // --------------------------------------------------------------------------
  // Reactive watch
  // --------------------------------------------------------------------------

  /// Returns a broadcast [Stream] that emits:
  /// 1. The **current** value for [key] immediately upon subscription.
  /// 2. Every subsequent value after a [write] or `null` after a [delete] /
  ///    [clear] that affects [key].
  ///
  /// The stream never closes on its own; cancel the subscription when no
  /// longer needed.
  Stream<String?> watch(String key);
}
