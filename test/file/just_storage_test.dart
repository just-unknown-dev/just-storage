@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('just_storage_factory_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  test('two encrypted() handles keep each other\'s keys', () async {
    final dir = _tempDir();
    final a = await JustStorage.encrypted(dir);
    final b = await JustStorage.encrypted(dir);
    await a.write('a', '1');
    await b.write('b', '2');
    final fresh = EncryptedFileStorage(dir);
    expect(await fresh.readAll(), {'a': '1', 'b': '2'});
  });

  test('two standard() handles keep each other\'s keys', () async {
    final dir = _tempDir();
    final a = await JustStorage.standard(dir);
    final b = await JustStorage.standard(dir);
    await a.write('a', '1');
    await b.write('b', '2');
    expect(await FileStorage(dir).readAll(), {'a': '1', 'b': '2'});
  });

  test('one instance per folder, however it is spelled', () async {
    final dir = _tempDir();
    final sub = Directory('${dir.path}${Platform.pathSeparator}sub')
      ..createSync();
    final spellings = [
      sub,
      Directory('${sub.path}${Platform.pathSeparator}'),
      Directory(
        '${sub.path}${Platform.pathSeparator}..${Platform.pathSeparator}sub',
      ),
      if (Platform.isWindows) Directory(sub.path.toUpperCase()),
    ];
    final standard = {
      for (final d in spellings)
        identityHashCode(await JustStorage.standard(d)),
    };
    final encrypted = {
      for (final d in spellings)
        identityHashCode(await JustStorage.encrypted(d)),
    };
    expect(standard, hasLength(1));
    expect(encrypted, hasLength(1));
  });

  test('different folders get different instances', () async {
    final a = await JustStorage.standard(_tempDir());
    final b = await JustStorage.standard(_tempDir());
    expect(identical(a, b), isFalse);
  });

  test('standard and encrypted over one folder keep separate files', () async {
    final dir = _tempDir();
    final plain = await JustStorage.standard(dir);
    final secure = await JustStorage.encrypted(dir);
    await plain.write('k', 'plain');
    await secure.write('k', 'secret');
    expect(await plain.read('k'), 'plain');
    expect(await secure.read('k'), 'secret');
  });
}
