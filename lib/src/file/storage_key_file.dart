import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal, visibleForTesting;

import '../core/core.dart';
import 'aes_gcm_cipher.dart';
import 'atomic_file.dart';

/// The 256-bit key an `EncryptedFileStorage` encrypts its values with: the
/// file `.storage.key` beside them.
///
/// The key is only as safe as that file. It is made with owner-only
/// permissions — `0600` on Linux and macOS, an access list naming only the
/// user on Windows — so other accounts on the machine can't read it; on
/// Android and iOS the app's own folder already keeps other apps out. Anyone
/// who can read the user's files (the user, an administrator, malware
/// running as the user, a backup) can read the key as well as the values.
@internal
final class StorageKeyFile {
  /// The key file in [directory].
  StorageKeyFile(Directory directory)
    : file = File('${directory.path}${Platform.pathSeparator}$fileName');

  /// The key file's name.
  static const String fileName = '.storage.key';

  /// The key file.
  final File file;

  /// The keys being read or made in this process, by file, so two storages
  /// over one folder never make two keys.
  static final Map<String, Future<Uint8List>> _inFlight = {};

  /// How long a key file another process has claimed may stay empty before
  /// it is taken for one whose maker died.
  @visibleForTesting
  static Duration claimTimeout = const Duration(seconds: 1);

  /// The key, or `null` when there is no key file.
  ///
  /// Throws a [StorageCorruptException] when the file isn't a key.
  Future<Uint8List?> read() async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (e) {
      throw StorageException('Could not read ${file.path}.', cause: e);
    }
    if (bytes.length != AesGcmCipher.keyLength) {
      throw StorageCorruptException(
        file.path,
        'holds ${bytes.length} bytes, not a ${AesGcmCipher.keyLength}-byte '
        'key.',
      );
    }
    return bytes;
  }

  /// The key, made now if there is no key file.
  ///
  /// With [replaceDamaged], a key file that isn't a key is replaced too —
  /// for when nothing sealed with it is kept. Without it, such a file throws
  /// a [StorageCorruptException].
  Future<Uint8List> readOrCreate({bool replaceDamaged = false}) {
    final id = file.absolute.path;
    return _inFlight[id] ??= _readOrCreate(replaceDamaged).whenComplete(() {
      // A block, not `=>`: the removed value is this very future, and
      // whenComplete would wait for a future its callback returns.
      _inFlight.remove(id);
    });
  }

  Future<Uint8List> _readOrCreate(bool replaceDamaged) async {
    final waitUntil = DateTime.now().add(claimTimeout);
    while (true) {
      try {
        final key = await read();
        if (key != null) return key;
      } on StorageCorruptException {
        // Empty: another process has claimed the name and is writing its
        // key. Wait for it, unless it has been empty too long.
        final empty = await _isEmpty();
        if (empty && DateTime.now().isBefore(waitUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          continue;
        }
        if (!replaceDamaged && !empty) rethrow;
        if (!replaceDamaged) {
          throw StorageCorruptException(
            file.path,
            'is empty: the program making it stopped before it wrote the '
            'key.',
          );
        }
        await _delete();
      }
      // Claim the name; of two makers, only one succeeds.
      try {
        await file.parent.create(recursive: true);
        await file.create(exclusive: true);
      } on FileSystemException catch (e) {
        if (!await file.exists()) {
          throw StorageException('Could not make ${file.path}.', cause: e);
        }
        // Someone else claimed it first: read their key.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      final key = AesGcmCipher.randomBytes(AesGcmCipher.keyLength);
      try {
        await AtomicFile.write(file, key, prepare: _ownerOnly);
      } catch (e) {
        await _delete();
        throw StorageException('Could not write ${file.path}.', cause: e);
      }
      return key;
    }
  }

  /// Deletes the key file. Every value sealed with it can no longer be read.
  Future<void> delete() => _delete();

  Future<void> _delete() async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    } on FileSystemException catch (e) {
      throw StorageException('Could not delete ${file.path}.', cause: e);
    }
  }

  Future<bool> _isEmpty() async {
    try {
      return await file.length() == 0;
    } on FileSystemException {
      return false;
    }
  }

  /// Narrows [temp]'s permissions to its owner, where the platform needs it
  /// and allows it. Best effort: when it fails, the folder's own
  /// permissions still apply.
  static Future<void> _ownerOnly(File temp) async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', temp.path]);
      } else if (Platform.isWindows) {
        final user = Platform.environment['USERNAME'];
        if (user == null || user.isEmpty) return;
        final domain = Platform.environment['USERDOMAIN'];
        final account = domain == null || domain.isEmpty
            ? user
            : '$domain\\$user';
        // Drop the inherited entries and grant the user alone.
        await Process.run('icacls', [
          temp.path,
          '/inheritance:r',
          '/grant:r',
          '$account:F',
        ]);
      }
      // Android and iOS: the app's folder is private to the app already,
      // and iOS can't start a process.
    } catch (_) {
      // No chmod or icacls here: leave the folder's permissions.
    }
  }
}
