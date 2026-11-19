@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/file/atomic_file.dart';

import '../support/storage_contract.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('just_storage_file_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  group('FileStorage contract', () {
    storageContract(() {
      late Directory dir;
      return (
        open: () async => FileStorage(dir = _tempDir()),
        reopen: () async => FileStorage(dir),
      );
    });
  });

  group('FileStorage', () {
    test('keeps plain JSON in just_storage.json', () async {
      final dir = _tempDir();
      final s = FileStorage(dir);
      await s.write('theme', 'dark');
      expect(s.file.path, endsWith(FileStorage.fileName));
      expect(jsonDecode(s.file.readAsStringSync()), {'theme': 'dark'});
    });

    test('writes made together share a save', () async {
      final s = FileStorage(_tempDir());
      await s.write('warm', 'up');
      final before = AtomicFile.writesStarted;
      await Future.wait([for (var i = 0; i < 100; i++) s.write('k$i', '$i')]);
      expect(AtomicFile.writesStarted - before, lessThanOrEqualTo(2));
      expect((await FileStorage(s.directory).readAll()).length, 101);
    });

    test('writing the value the file holds does not write the file', () async {
      final s = FileStorage(_tempDir());
      await s.write('k', 'v');
      final old = DateTime(2001);
      s.file.setLastModifiedSync(old);
      await s.write('k', 'v');
      expect(s.file.lastModifiedSync(), old);
      await s.write('k', 'w');
      expect(s.file.lastModifiedSync(), isNot(old));
    });

    group('a file that cannot be read', () {
      Future<FileStorage> withFile(List<int> bytes) async {
        final dir = _tempDir();
        File(
          '${dir.path}${Platform.pathSeparator}${FileStorage.fileName}',
        ).writeAsBytesSync(bytes);
        return FileStorage(dir);
      }

      for (final (name, bytes) in [
        ('not JSON', utf8.encode('{"a": ')),
        ('a JSON array', utf8.encode('["a"]')),
        ('not UTF-8', [0x7B, 0xFF, 0xFE, 0x7D]),
        ('empty', <int>[]),
      ]) {
        test('$name: every call throws and the file is left alone', () async {
          final s = await withFile(bytes);
          await expectLater(
            s.read('a'),
            throwsA(isA<StorageCorruptException>()),
          );
          await expectLater(
            s.write('a', '1'),
            throwsA(isA<StorageCorruptException>()),
          );
          await expectLater(
            s.readAll(),
            throwsA(isA<StorageCorruptException>()),
          );
          expect(s.file.readAsBytesSync(), bytes);
        });
      }

      test('values that are not strings name their keys', () async {
        final s = await withFile(utf8.encode('{"ok": "1", "n": 2, "b": true}'));
        await expectLater(
          s.read('ok'),
          throwsA(
            isA<StorageCorruptException>().having(
              (e) => e.keys,
              'keys',
              unorderedEquals(['n', 'b']),
            ),
          ),
        );
      });

      test('clear starts over with an empty store', () async {
        final s = await withFile(utf8.encode('garbage'));
        final watched = <String?>[];
        final sub = s.watch('a').listen(watched.add, onError: (Object _) {});
        await pumpEventQueue();
        await s.clear();
        expect(await s.readAll(), isEmpty);
        await s.write('a', '1');
        expect(await FileStorage(s.directory).readAll(), {'a': '1'});
        await sub.cancel();
        expect(watched, [null, '1']);
      });

      test('it is read again once it is put right', () async {
        final s = await withFile(utf8.encode('garbage'));
        await expectLater(s.read('a'), throwsA(isA<StorageException>()));
        s.file.writeAsStringSync('{"a": "fixed"}');
        expect(await s.read('a'), 'fixed');
      });

      test('a watcher gets the error first', () async {
        final s = await withFile(utf8.encode('garbage'));
        await expectLater(
          s.watch('a').first,
          throwsA(isA<StorageCorruptException>()),
        );
      });
    });

    group('a save that fails', () {
      /// A storage whose next save fails: its file's name is taken by a
      /// folder, which no file can be renamed over.
      Future<FileStorage> failing() async {
        final s = FileStorage(_tempDir());
        await s.write('kept', 'old');
        s.file.deleteSync();
        Directory(s.file.path).createSync();
        return s;
      }

      test('throws, and the value goes back to what the file held', () async {
        final s = await failing();
        await expectLater(
          s.write('kept', 'new'),
          throwsA(isA<StorageException>()),
        );
        await expectLater(
          s.write('added', 'x'),
          throwsA(isA<StorageException>()),
        );
        expect(await s.read('kept'), 'old');
        expect(await s.containsKey('added'), isFalse);
      });

      test('is not sent to watchers', () async {
        final s = await failing();
        final seen = <String?>[];
        final sub = s.watch('kept').listen(seen.add);
        await pumpEventQueue();
        await expectLater(
          s.write('kept', 'new'),
          throwsA(isA<StorageException>()),
        );
        await pumpEventQueue();
        await sub.cancel();
        expect(seen, ['old']);
      });

      test('leaves no temporary file behind', () async {
        final s = await failing();
        await expectLater(s.write('k', 'v'), throwsA(isA<StorageException>()));
        final temps = s.directory.listSync().where(
          (e) => e.path.contains('.tmp.'),
        );
        expect(temps, isEmpty);
      });

      test('the next save after the cause is gone writes it all', () async {
        final s = await failing();
        await expectLater(s.write('k', 'v'), throwsA(isA<StorageException>()));
        Directory(s.file.path).deleteSync();
        await s.write('k', 'v');
        expect(await FileStorage(s.directory).readAll(), {
          'kept': 'old',
          'k': 'v',
        });
      });
    });

    group('dispose', () {
      test('waits for the saves under way', () async {
        final s = FileStorage(_tempDir());
        unawaited(s.write('a', '1'));
        unawaited(s.write('b', '2'));
        await s.dispose();
        expect(await FileStorage(s.directory).readAll(), {'a': '1', 'b': '2'});
      });

      test('ends the watch streams', () async {
        final s = FileStorage(_tempDir());
        final done = doneOf(s.watch('k'));
        await pumpEventQueue();
        await s.dispose();
        await done.timeout(const Duration(seconds: 5));
      });

      test('leaves a storage that still works', () async {
        final s = FileStorage(_tempDir());
        await s.write('a', '1');
        await s.dispose();
        expect(await s.read('a'), '1');
        await s.write('b', '2');
        expect(await FileStorage(s.directory).readAll(), {'a': '1', 'b': '2'});
      });
    });

    test('old temporary files are swept, fresh ones left', () async {
      final dir = _tempDir();
      final s = FileStorage(dir);
      final old = File('${s.file.path}.tmp.1.0')..writeAsStringSync('{}');
      old.setLastModifiedSync(DateTime(2001));
      final fresh = File('${s.file.path}.tmp.2.0')..writeAsStringSync('{}');
      await s.read('a');
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });
  });
}
