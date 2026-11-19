import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/core.dart';
import '../core/sealed_value.dart';
import 'aes_gcm_cipher.dart';
import 'file_store.dart';
import 'just_storage.dart';
import 'storage_key_file.dart';

/// [JustSecureStorage] for native platforms: every value encrypted with
/// AES-256-GCM, in one file, `<directory>/just_secure_storage.enc`.
///
/// ### The file
/// ```json
/// {
///   "v": 2,
///   "entries": {
///     "access_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext + tag>" }
///   }
/// }
/// ```
/// Each value is encrypted on its own, with a random 12-byte nonce and its
/// key as additional authenticated data: a value that was changed, or moved
/// to another key, fails its 16-byte GCM tag check. Only values that changed
/// are encrypted again when the file is saved.
///
/// The keys themselves are not encrypted; don't put secrets in them.
///
/// ### The key
/// One random 256-bit key, in `<directory>/.storage.key`, readable only by
/// its owner on desktop platforms. It is made on the first write, and never
/// made again while the file holds values sealed with it: if it goes
/// missing or is damaged, every call throws a [StorageCorruptException]
/// until [clear] starts over.
///
/// ### Saving
/// As [FileStorage]: read once, written back whole after every change, a
/// temporary file renamed over the old one, writes made close together
/// sharing one save. A file that can't be read or decrypted throws a
/// [StorageCorruptException] and is left alone until [clear].
///
/// Files written before 2.0.0 (without the key bound to each value) are
/// read, and written again in this format straight away.
///
/// Get one from [JustStorage.encrypted], which hands everyone the same
/// instance for a folder.
class EncryptedFileStorage extends JustSecureStorage {
  /// A storage keeping its files in [directory].
  ///
  /// Prefer [JustStorage.encrypted]; make one directly only where nothing
  /// else opens [directory], as in a test.
  EncryptedFileStorage(Directory directory)
    : this._(directory, StorageKeyFile(directory));

  EncryptedFileStorage._(Directory directory, StorageKeyFile keyFile)
    : _keyFile = keyFile,
      _store = FileStore(directory, fileName, _SealedJson(keyFile));

  /// The name of the file in [directory] that holds the values.
  static const String fileName = 'just_secure_storage.enc';

  final StorageKeyFile _keyFile;
  final FileStore _store;

  /// The folder the files are in.
  Directory get directory => _store.directory;

  /// The file the encrypted values are kept in.
  File get file => _store.file;

  /// The file the key is kept in.
  File get keyFile => _keyFile.file;

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<void> delete(String key) => _store.delete(key);

  /// Removes every value. Over a file that can't be read or decrypted, or a
  /// key that is missing or damaged, it starts over with an empty file and,
  /// on the next write, a new key.
  @override
  Future<void> clear() => _store.clear();

  @override
  Future<bool> containsKey(String key) => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll() => _store.readAll();

  @override
  Stream<String?> watch(String key) => _store.watch(key);

  /// Waits for the saves under way, then ends every [watch] stream and lets
  /// go of the values and the key in memory.
  ///
  /// The storage still works afterwards: the next call reads the files
  /// again. An instance from [JustStorage.encrypted] is shared, so disposing
  /// it ends the streams of everyone using it.
  Future<void> dispose() => _store.dispose();

  /// Removes every value and deletes the key file, so nothing written so far
  /// can be decrypted again, even from a copy of the files. The next write
  /// makes a new key.
  Future<void> wipe() => _store.clear(wipe: true);
}

/// The file format: `{"v": 2, "entries": {key: sealed value}}`, or a
/// version 1 file — the entries alone, sealed without additional data.
final class _SealedJson implements FileStoreCodec {
  _SealedJson(this._keyFile);

  final StorageKeyFile _keyFile;
  static const _cipher = AesGcmCipher();

  /// The key, once read or made.
  Uint8List? _key;

  /// Each entry's sealed value as last read or written, with the value it
  /// seals — so a save encrypts again only the values that changed.
  final Map<String, ({String value, Map<String, String> json})> _sealed = {};

  /// Whether the file may hold values sealed with the key file's key, so
  /// the key must not be replaced.
  bool _keyInUse = false;

  bool _oldFormat = false;

  @override
  bool get wantsRewrite => _oldFormat;

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
    final int version;
    final Map<String, dynamic> sealed;
    final v = json['v'];
    if (v is int) {
      if (v != SealedValue.current) {
        throw StorageCorruptException(
          path,
          'is in format $v; this version of just_storage reads '
          'format ${SealedValue.current}.',
        );
      }
      final entries = json['entries'];
      if (entries is! Map<String, dynamic>) {
        throw StorageCorruptException(path, 'has no "entries" object.');
      }
      version = v;
      sealed = entries;
    } else {
      // Version 1: the entries were the whole object.
      version = 1;
      sealed = json;
    }
    _sealed.clear();
    _oldFormat = version < SealedValue.current && sealed.isNotEmpty;
    _keyInUse = sealed.isNotEmpty;
    if (sealed.isEmpty) return {};

    final key = await _keyFile.read();
    if (key == null) {
      throw StorageCorruptException(
        path,
        'holds encrypted values, but their key ${_keyFile.file.path} is '
        'missing.',
      );
    }
    _key = key;

    final entries = <String, String>{};
    final unreadable = <String>[];
    for (final MapEntry(key: name, :value) in sealed.entries) {
      try {
        final parts = SealedValue.fromJson(value);
        final plain = _cipher.open(
          key,
          parts.nonce,
          parts.ciphertext,
          SealedValue.aadFor(name, version),
        );
        final text = utf8.decode(plain);
        entries[name] = text;
        if (version == SealedValue.current) {
          _sealed[name] = (value: text, json: parts.toJson());
        }
      } on FormatException {
        unreadable.add(name);
      } on StorageException {
        unreadable.add(name);
      }
    }
    if (unreadable.isNotEmpty) {
      throw StorageCorruptException(
        path,
        unreadable.length == sealed.length
            ? 'none of its values can be decrypted with the key in '
                  '${_keyFile.file.path}: the key is not theirs, or they '
                  'were changed.'
            : 'some values can\'t be decrypted: they were changed, or '
                  'moved from another key.',
        keys: unreadable,
      );
    }
    return entries;
  }

  @override
  Future<String> encode(Map<String, String> entries) async {
    final out = <String, Map<String, String>>{};
    if (entries.isNotEmpty) {
      final key = _key ??= await _keyFile.readOrCreate(
        replaceDamaged: !_keyInUse,
      );
      _keyInUse = true;
      for (final MapEntry(key: name, :value) in entries.entries) {
        final known = _sealed[name];
        if (known != null && known.value == value) {
          out[name] = known.json;
          continue;
        }
        final sealed = _cipher.seal(
          key,
          Uint8List.fromList(utf8.encode(value)),
          SealedValue.aadFor(name, SealedValue.current),
        );
        final json = SealedValue(sealed.nonce, sealed.ciphertext).toJson();
        _sealed[name] = (value: value, json: json);
        out[name] = json;
      }
    }
    _sealed.removeWhere((name, _) => !entries.containsKey(name));
    _oldFormat = false;
    return jsonEncode({'v': SealedValue.current, 'entries': out});
  }

  @override
  Future<void> forget({required bool unreadable, required bool wipe}) async {
    _sealed.clear();
    _oldFormat = false;
    if (unreadable || wipe) {
      // Values that can't be read make their key worth nothing, and a wipe
      // must not leave one that could read a copy: the next write makes a
      // new key.
      _key = null;
      _keyInUse = false;
      await _keyFile.delete();
    }
  }
}
