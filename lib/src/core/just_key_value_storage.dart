import 'dart:convert';

import 'just_secure_storage.dart';
import 'just_standard_storage.dart';
import 'storage_exception.dart';

/// What [JustStandardStorage] and [JustSecureStorage] have in common: a
/// persistent map from string keys to string values, with JSON helpers and a
/// stream of each key's values.
///
/// The two subtypes differ in where the values go, not in what they can do:
/// ask for a [JustSecureStorage] wherever a value must not be readable on
/// disk. Code that works with either can take a [JustKeyValueStorage].
abstract class JustKeyValueStorage {
  /// Constructor for subclasses.
  const JustKeyValueStorage();

  /// The value stored under [key], or `null` if there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing what was there.
  ///
  /// When the returned future completes, the value is saved: a fresh
  /// storage over the same place reads it back.
  Future<void> write(String key, String value);

  /// Removes [key] and its value. Does nothing if there is none.
  Future<void> delete(String key);

  /// Removes every key this storage holds.
  ///
  /// This also works when the storage can't be read
  /// ([StorageCorruptException]): what is there is replaced with an empty
  /// store.
  Future<void> clear();

  /// Whether [key] holds a value, even an empty one.
  Future<bool> containsKey(String key);

  /// Every key and its value, as an unmodifiable copy.
  Future<Map<String, String>> readAll();

  /// Reads the value under [key] as a JSON object and builds a [T] from it
  /// with [fromJson]. Returns `null` when [key] holds nothing.
  ///
  /// Throws a [StorageException] when the value isn't a JSON object, or when
  /// [fromJson] throws.
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    final raw = await read(key);
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw StorageException('The value of "$key" is not JSON.', cause: e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw StorageException('The value of "$key" is not a JSON object.');
    }
    try {
      return fromJson(decoded);
    } catch (e) {
      throw StorageException(
        'Could not build a value from the JSON of "$key".',
        cause: e,
      );
    }
  }

  /// Turns [value] into a JSON object with [toJson] and stores it under
  /// [key].
  ///
  /// Throws a [StorageException] when [toJson] throws or returns something
  /// JSON can't hold.
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) async {
    final String encoded;
    try {
      encoded = jsonEncode(toJson(value));
    } catch (e) {
      throw StorageException('Could not turn "$key" into JSON.', cause: e);
    }
    await write(key, encoded);
  }

  /// The values [key] takes, as they change.
  ///
  /// Each listener first gets the value [key] holds when it starts
  /// listening (`null` for none), then every value [key] takes after that,
  /// and `null` when it is deleted or the storage is cleared. Listen as
  /// often as you like: it is a broadcast stream, and each listener gets its
  /// own first value.
  ///
  /// The stream ends only when the storage is disposed; cancel the
  /// subscription when you no longer need it. If the storage can't be read,
  /// a listener gets the [StorageException] in place of the first value, and
  /// the values that follow once it can.
  Stream<String?> watch(String key);
}
