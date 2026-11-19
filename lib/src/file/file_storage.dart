import 'dart:convert';
import 'dart:io';

import '../core/core.dart';
import 'file_store.dart';
import 'just_storage.dart';

/// [JustStandardStorage] for native platforms: the values as plain JSON in
/// one file, `<directory>/just_storage.json`.
///
/// The whole file is read into memory on first use and written back after
/// every change; writes made close together share one save. Each save
/// writes a temporary file and renames it over the old one, so a crash
/// leaves the old file or the new one, never half of one.
///
/// A file that isn't the JSON this writes — damaged, or edited by hand —
/// makes every call throw a [StorageCorruptException]; the file is left as
/// it is until [clear] replaces it.
///
/// Get one from [JustStorage.standard], which hands everyone the same
/// instance for a folder. Two instances over one folder would each write
/// their own copy of the file over the other's.
class FileStorage extends JustStandardStorage {
  /// A storage keeping its file in [directory].
  ///
  /// Prefer [JustStorage.standard]; make one directly only where nothing
  /// else opens [directory], as in a test.
  FileStorage(Directory directory)
    : _store = FileStore(directory, fileName, const _PlainJson());

  /// The name of the file in [directory].
  static const String fileName = 'just_storage.json';

  final FileStore _store;

  /// The folder the file is in.
  Directory get directory => _store.directory;

  /// The file the values are kept in.
  File get file => _store.file;

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<void> delete(String key) => _store.delete(key);

  @override
  Future<void> clear() => _store.clear();

  @override
  Future<bool> containsKey(String key) => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll() => _store.readAll();

  @override
  Stream<String?> watch(String key) => _store.watch(key);

  /// Waits for the saves under way, then ends every [watch] stream and lets
  /// go of the values in memory.
  ///
  /// The storage still works afterwards: the next call reads the file
  /// again. An instance from [JustStorage.standard] is shared, so disposing
  /// it ends the streams of everyone using it.
  Future<void> dispose() => _store.dispose();
}

final class _PlainJson implements FileStoreCodec {
  const _PlainJson();

  @override
  Future<Map<String, String>> decode(String text, String path) async {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw StorageCorruptException(path, 'is not JSON.', cause: e);
    }
    if (json is! Map<String, dynamic>) {
      throw StorageCorruptException(path, 'is not a JSON object.');
    }
    final entries = <String, String>{};
    final notText = <String>[];
    for (final MapEntry(:key, :value) in json.entries) {
      if (value is String) {
        entries[key] = value;
      } else {
        notText.add(key);
      }
    }
    if (notText.isNotEmpty) {
      throw StorageCorruptException(
        path,
        'holds values that are not strings.',
        keys: notText,
      );
    }
    return entries;
  }

  @override
  Future<String> encode(Map<String, String> entries) async =>
      jsonEncode(entries);

  @override
  Future<void> forget({required bool unreadable, required bool wipe}) async {}

  @override
  bool get wantsRewrite => false;
}
