/// What the admin screen asks of the platform on Android, iOS, Linux, macOS
/// and Windows: where a storage's files are, wiping one, and export files in
/// the Downloads folder — not exported.
@internal
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show internal;
import 'package:path_provider/path_provider.dart';

import '../core/admin_types.dart';
import '../core/core.dart';
import 'encrypted_file_storage.dart';
import 'file_storage.dart';
import 'storage_key_file.dart';

/// Where [storage] keeps its values; null for a storage this package
/// didn't make.
@internal
Future<StoreDescription?> describeStorage(JustKeyValueStorage storage) async {
  if (storage is FileStorage) {
    final stat = await _stat(storage.file);
    return StoreDescription(
      medium: 'JSON file',
      sizeBytes: stat?.size,
      modified: stat?.modified,
      facts: [
        StoreFact('Folder', storage.directory.path, path: true),
        StoreFact('File', FileStorage.fileName, path: true),
        if (stat == null) const StoreFact('On disk', 'Not written yet'),
        const StoreFact(
          'Format',
          'Plain JSON, one object of every key and value: anyone who can '
              'read the folder can read them',
        ),
      ],
    );
  }
  if (storage is EncryptedFileStorage) {
    final stat = await _stat(storage.file);
    final key = await _stat(storage.keyFile);
    return StoreDescription(
      medium: 'Encrypted file',
      sizeBytes: stat?.size,
      modified: stat?.modified,
      canWipe: true,
      facts: [
        StoreFact('Folder', storage.directory.path, path: true),
        StoreFact('File', EncryptedFileStorage.fileName, path: true),
        if (stat == null) const StoreFact('On disk', 'Not written yet'),
        const StoreFact(
          'Format',
          'Version 2: each value sealed with AES-256-GCM and bound to its '
              'key',
        ),
        StoreFact(
          'Key file',
          key == null
              ? '${StorageKeyFile.fileName}: none yet, the first write '
                    'makes it'
              : '${StorageKeyFile.fileName}, beside the values',
          path: key != null,
        ),
        StoreFact(
          'Key access',
          Platform.isAndroid || Platform.isIOS
              ? 'Inside the app\'s sandbox, and in its device backups'
              : 'Readable by its owner only — and by anything running as '
                    'that user',
        ),
      ],
    );
  }
  return null;
}

Future<FileStat?> _stat(File file) async {
  final stat = await file.stat();
  return stat.type == FileSystemEntityType.notFound ? null : stat;
}

/// Whether [storage] can be wiped: emptied, with its key destroyed.
@internal
bool canWipe(JustKeyValueStorage storage) => storage is EncryptedFileStorage;

/// Empties [storage] and destroys its key; see [canWipe].
@internal
Future<void> wipeStorage(JustKeyValueStorage storage) =>
    (storage as EncryptedFileStorage).wipe();

/// Whether [pickTextFile] can show a file picker here: not on native
/// platforms, without a plugin.
@internal
const bool canPickFiles = false;

/// Whether a file can be read from a path the user types.
@internal
bool get canReadTypedPaths =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<Directory> _exportsFolder() async {
  Directory? base;
  try {
    base = await getDownloadsDirectory();
  } catch (_) {
    // Not every platform (or test double) has a Downloads folder.
  }
  base ??= await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}just_storage');
  await dir.create(recursive: true);
  return dir;
}

/// The folder exports are saved in.
@internal
Future<String?> exportsLocation() async => (await _exportsFolder()).path;

/// Saves [content] as [fileName] in the exports folder, replacing a file of
/// that name, and says where it went.
@internal
Future<String> saveExport(String fileName, String content) async {
  final dir = await _exportsFolder();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(content, flush: true);
  if (await file.exists()) await file.delete();
  await temp.rename(file.path);
  return file.path;
}

/// The files in the exports folder, newest first.
@internal
Future<List<ExportFile>> listExports() async {
  final dir = await _exportsFolder();
  final found = <ExportFile>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || entity.path.endsWith('.tmp')) continue;
    final stat = await entity.stat();
    found.add(
      ExportFile(
        name: entity.uri.pathSegments.last,
        path: entity.path,
        sizeBytes: stat.size,
        modified: stat.modified,
      ),
    );
  }
  found.sort((a, b) => b.modified.compareTo(a.modified));
  return found;
}

/// The text of the file at [path].
@internal
Future<String> readExport(String path) => File(path).readAsString();

/// Lets the user pick a text file; never available here (see
/// [canPickFiles]).
@internal
Future<PickedTextFile?> pickTextFile() async => null;
