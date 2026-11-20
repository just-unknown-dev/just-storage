@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/file/admin_support.dart';

import '../support/memory_storage.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('just_storage_admin_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('describes a file storage: where, how big, not wipeable', () async {
    final s = FileStorage(_tempDir());
    var d = (await describeStorage(s))!;
    expect(d.medium, 'JSON file');
    expect(d.sizeBytes, isNull, reason: 'nothing written yet');
    expect(d.facts.map((f) => f.label), contains('On disk'));
    expect(d.canWipe, isFalse);
    expect(canWipe(s), isFalse);

    await s.write('k', 'v');
    d = (await describeStorage(s))!;
    expect(d.sizeBytes, s.file.lengthSync());
    expect(d.modified, isNotNull);
    final folder = d.facts.firstWhere((f) => f.label == 'Folder');
    expect(folder.value, s.directory.path);
    expect(folder.path, isTrue);
  });

  test('describes an encrypted storage and its key, and wipes it', () async {
    final s = EncryptedFileStorage(_tempDir());
    var d = (await describeStorage(s))!;
    expect(d.medium, 'Encrypted file');
    expect(d.canWipe, isTrue);
    expect(
      d.facts.firstWhere((f) => f.label == 'Key file').value,
      contains('none yet'),
    );

    await s.write('token', 'secret');
    d = (await describeStorage(s))!;
    expect(d.sizeBytes, greaterThan(0));
    expect(
      d.facts.firstWhere((f) => f.label == 'Key file').value,
      isNot(contains('none yet')),
    );
    expect(s.keyFile.existsSync(), isTrue);

    expect(canWipe(s), isTrue);
    await wipeStorage(s);
    expect(await s.readAll(), isEmpty);
    expect(s.keyFile.existsSync(), isFalse);
  });

  test('says nothing of a storage it did not make', () async {
    expect(await describeStorage(MemoryStandardStorage()), isNull);
    expect(canWipe(MemorySecureStorage()), isFalse);
  });
}
