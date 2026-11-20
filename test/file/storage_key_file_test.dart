@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/file/aes_gcm_cipher.dart';
import 'package:just_storage/src/file/storage_key_file.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('just_storage_key_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  late Duration timeout;
  setUp(() => timeout = StorageKeyFile.claimTimeout);
  tearDown(() => StorageKeyFile.claimTimeout = timeout);

  test('no file: read is null, readOrCreate makes one key and keeps '
      'it', () async {
    final keys = StorageKeyFile(_tempDir());
    expect(await keys.read(), isNull);
    final made = await keys.readOrCreate();
    expect(made, hasLength(AesGcmCipher.keyLength));
    expect(await keys.readOrCreate(), made);
    expect(await keys.read(), made);
  });

  test('callers at once in one process get one key', () async {
    final dir = _tempDir();
    final keys = await Future.wait([
      for (var i = 0; i < 5; i++) StorageKeyFile(dir).readOrCreate(),
    ]);
    for (final key in keys) {
      expect(key, keys.first);
    }
  });

  test('a file that is not a key throws, unless it may be replaced', () async {
    final keys = StorageKeyFile(_tempDir());
    keys.file.writeAsBytesSync([1, 2, 3]);
    await expectLater(keys.read(), throwsA(isA<StorageCorruptException>()));
    await expectLater(
      keys.readOrCreate(),
      throwsA(isA<StorageCorruptException>()),
    );
    final made = await keys.readOrCreate(replaceDamaged: true);
    expect(made, hasLength(AesGcmCipher.keyLength));
  });

  test('an empty file another process is filling is waited for', () async {
    final keys = StorageKeyFile(_tempDir());
    keys.file.createSync();
    final theirs = AesGcmCipher.randomBytes(AesGcmCipher.keyLength);
    Timer(
      const Duration(milliseconds: 100),
      () => keys.file.writeAsBytesSync(theirs),
    );
    expect(await keys.readOrCreate(), theirs);
  });

  test('an empty file nobody fills: throws, or is replaced', () async {
    StorageKeyFile.claimTimeout = const Duration(milliseconds: 50);
    final keys = StorageKeyFile(_tempDir());
    keys.file.createSync();
    await expectLater(
      keys.readOrCreate(),
      throwsA(isA<StorageCorruptException>()),
    );
    final made = await keys.readOrCreate(replaceDamaged: true);
    expect(made, hasLength(AesGcmCipher.keyLength));
  });

  test('a folder that cannot hold it fails rather than spins', () async {
    final dir = _tempDir();
    // A file where the folder should be.
    final blocker = File('${dir.path}${Platform.pathSeparator}blocked')
      ..writeAsStringSync('');
    final keys = StorageKeyFile(Directory(blocker.path));
    await expectLater(
      keys.readOrCreate().timeout(const Duration(seconds: 10)),
      throwsA(isA<StorageException>()),
    );
  });

  test('delete removes it, and is fine when it is gone', () async {
    final keys = StorageKeyFile(_tempDir());
    await keys.readOrCreate();
    await keys.delete();
    expect(keys.file.existsSync(), isFalse);
    await keys.delete();
  });
}
