// In-memory storages for widget tests: no files, no timers.

import 'dart:async';

import 'package:just_storage/just_storage.dart';

/// What [MemoryStandardStorage] and [MemorySecureStorage] do.
mixin MemoryStorage on JustKeyValueStorage {
  final Map<String, String> values = {};
  final _changes = StreamController<(String, String?)>.broadcast(sync: true);
  final _storageChanges = StreamController<StorageChange>.broadcast();

  /// Thrown by every call while set, as by a storage that can't be read.
  Object? failure;

  /// Completed before every read when set, to hold reads back.
  Completer<void>? gate;

  /// How many times [clear] was called.
  int clears = 0;

  Future<void> _ready() async {
    await gate?.future;
    if (failure case final failure?) throw failure;
  }

  @override
  Future<String?> read(String key) async {
    await _ready();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await _ready();
    values[key] = value;
    _changes.add((key, value));
    _storageChanges.add(StorageChange(key, value));
  }

  @override
  Future<void> delete(String key) async {
    await _ready();
    values.remove(key);
    _changes.add((key, null));
    _storageChanges.add(StorageChange(key, null));
  }

  @override
  Future<void> clear() async {
    clears++;
    failure = null;
    final keys = [...values.keys];
    values.clear();
    for (final key in keys) {
      _changes.add((key, null));
    }
    _storageChanges.add(const StorageChange.cleared());
  }

  @override
  Stream<StorageChange> get changes => _storageChanges.stream;

  /// Changes [key] as another tab or process would: without the storage
  /// itself reporting it, unless [report].
  void changeBehindItsBack(String key, String? value, {bool report = true}) {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (report) _storageChanges.add(StorageChange(key, value));
  }

  @override
  Future<bool> containsKey(String key) async {
    await _ready();
    return values.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    await _ready();
    return Map.unmodifiable(values);
  }

  @override
  Stream<String?> watch(String key) async* {
    yield await read(key);
    yield* _changes.stream.where((c) => c.$1 == key).map((c) => c.$2);
  }
}

/// A [JustStandardStorage] in memory.
class MemoryStandardStorage extends JustStandardStorage with MemoryStorage {}

/// A [JustSecureStorage] in memory.
class MemorySecureStorage extends JustSecureStorage with MemoryStorage {}
