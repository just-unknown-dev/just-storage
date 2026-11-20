@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/core/sealed_value.dart';
import 'package:just_storage/src/file/aes_gcm_cipher.dart';

import '../support/storage_contract.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('just_storage_enc_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Map<String, dynamic> _fileJson(EncryptedFileStorage s) =>
    jsonDecode(s.file.readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _entries(EncryptedFileStorage s) =>
    _fileJson(s)['entries'] as Map<String, dynamic>;

void main() {
  group('EncryptedFileStorage contract', () {
    storageContract(() {
      late Directory dir;
      return (
        open: () async => EncryptedFileStorage(dir = _tempDir()),
        reopen: () async => EncryptedFileStorage(dir),
      );
    });
  });

  group('EncryptedFileStorage', () {
    test('keeps no plaintext on disk', () async {
      final s = EncryptedFileStorage(_tempDir());
      await s.write('token', 'super-secret-value');
      final text = s.file.readAsStringSync();
      expect(text, isNot(contains('super-secret-value')));
      expect(_fileJson(s)['v'], SealedValue.current);
      expect(s.keyFile.lengthSync(), AesGcmCipher.keyLength);
    });

    test('the same value is sealed with a different nonce each time', () async {
      final s = EncryptedFileStorage(_tempDir());
      await s.write('a', 'same');
      await s.write('b', 'same');
      final entries = _entries(s);
      expect((entries['a'] as Map)['n'], isNot((entries['b'] as Map)['n']));
      expect((entries['a'] as Map)['ct'], isNot((entries['b'] as Map)['ct']));
    });

    test('only values that changed are encrypted again', () async {
      final s = EncryptedFileStorage(_tempDir());
      await s.write('a', '1');
      await s.write('b', '2');
      final before = _entries(s);
      await s.write('c', '3');
      await s.write('b', '2');
      final after = _entries(s);
      expect(after['a'], before['a']);
      expect(after['b'], before['b']);
      // And a fresh instance reads the reused ones.
      expect(await EncryptedFileStorage(s.directory).readAll(), {
        'a': '1',
        'b': '2',
        'c': '3',
      });
    });

    group('a changed file', () {
      Future<EncryptedFileStorage> written() async {
        final s = EncryptedFileStorage(_tempDir());
        await s.write('role', 'user');
        await s.write('name', 'Ada');
        await s.dispose();
        return s;
      }

      void rewrite(
        EncryptedFileStorage s,
        void Function(Map<String, dynamic> entries) change,
      ) {
        final json = _fileJson(s);
        change(json['entries'] as Map<String, dynamic>);
        s.file.writeAsStringSync(jsonEncode(json));
      }

      test('a flipped bit fails, naming the key, and the file is left '
          'alone', () async {
        final s = await written();
        rewrite(s, (entries) {
          final sealed = entries['role'] as Map<String, dynamic>;
          final ct = base64.decode(sealed['ct'] as String);
          ct[0] ^= 1;
          sealed['ct'] = base64.encode(ct);
        });
        final bytes = s.file.readAsBytesSync();
        final fresh = EncryptedFileStorage(s.directory);
        await expectLater(
          fresh.read('name'),
          throwsA(
            isA<StorageCorruptException>().having((e) => e.keys, 'keys', [
              'role',
            ]),
          ),
        );
        await expectLater(
          fresh.write('x', 'y'),
          throwsA(isA<StorageCorruptException>()),
        );
        expect(s.file.readAsBytesSync(), bytes);
      });

      test('a value moved to another key fails', () async {
        final s = await written();
        rewrite(s, (entries) {
          final role = entries['role'];
          entries['role'] = entries['name'];
          entries['name'] = role;
        });
        await expectLater(
          EncryptedFileStorage(s.directory).read('role'),
          throwsA(isA<StorageCorruptException>()),
        );
      });

      test('a malformed entry fails', () async {
        final s = await written();
        rewrite(s, (entries) => entries['role'] = {'n': '!!', 'ct': 3});
        await expectLater(
          EncryptedFileStorage(s.directory).read('name'),
          throwsA(isA<StorageCorruptException>()),
        );
      });

      test('an unknown format version fails', () async {
        final s = await written();
        s.file.writeAsStringSync(jsonEncode({'v': 3, 'entries': {}}));
        await expectLater(
          EncryptedFileStorage(s.directory).read('name'),
          throwsA(isA<StorageCorruptException>()),
        );
      });

      test('clear starts over, with a new key', () async {
        final s = await written();
        rewrite(s, (entries) => entries['role'] = {'n': 'AAAA', 'ct': 'AAAA'});
        final oldKey = s.keyFile.readAsBytesSync();
        final fresh = EncryptedFileStorage(s.directory);
        await fresh.clear();
        expect(await fresh.readAll(), isEmpty);
        await fresh.write('role', 'admin');
        expect(s.keyFile.readAsBytesSync(), isNot(oldKey));
        expect(await EncryptedFileStorage(s.directory).readAll(), {
          'role': 'admin',
        });
      });
    });

    group('the key', () {
      test('missing beside values: fails, and no new key is made', () async {
        final s = EncryptedFileStorage(_tempDir());
        await s.write('a', '1');
        s.keyFile.deleteSync();
        final fresh = EncryptedFileStorage(s.directory);
        await expectLater(
          fresh.read('a'),
          throwsA(isA<StorageCorruptException>()),
        );
        await expectLater(
          fresh.write('b', '2'),
          throwsA(isA<StorageCorruptException>()),
        );
        expect(s.keyFile.existsSync(), isFalse);
      });

      test('damaged beside values: fails, until clear', () async {
        final s = EncryptedFileStorage(_tempDir());
        await s.write('a', '1');
        s.keyFile.writeAsBytesSync([1, 2, 3]);
        final fresh = EncryptedFileStorage(s.directory);
        await expectLater(
          fresh.read('a'),
          throwsA(isA<StorageCorruptException>()),
        );
        await fresh.clear();
        await fresh.write('b', '2');
        expect(s.keyFile.lengthSync(), AesGcmCipher.keyLength);
        expect(await EncryptedFileStorage(s.directory).readAll(), {'b': '2'});
      });

      test('damaged with no values: replaced on the next write', () async {
        final dir = _tempDir();
        final s = EncryptedFileStorage(dir);
        s.keyFile.writeAsBytesSync([1, 2, 3]);
        await s.write('a', '1');
        expect(s.keyFile.lengthSync(), AesGcmCipher.keyLength);
        expect(await EncryptedFileStorage(dir).read('a'), '1');
      });

      test('two storages over one folder make one key', () async {
        final dir = _tempDir();
        final a = EncryptedFileStorage(dir);
        final b = EncryptedFileStorage(dir);
        await Future.wait([a.write('a', '1'), b.write('b', '2')]);
        // One of the two files won; either way, it decrypts.
        final all = await EncryptedFileStorage(dir).readAll();
        expect(all, anyOf({'a': '1'}, {'b': '2'}));
      });

      test('is readable only by its owner', () async {
        final s = EncryptedFileStorage(_tempDir());
        await s.write('a', '1');
        if (Platform.isLinux || Platform.isMacOS) {
          final mode = s.keyFile.statSync().mode & 0x1FF;
          expect(mode & 0x3F, 0, reason: 'mode ${mode.toRadixString(8)}');
        } else if (Platform.isWindows) {
          final acl = Process.runSync('icacls', [s.keyFile.path]);
          final text = acl.stdout as String;
          expect(text, isNot(contains('(I)')), reason: text);
          expect(text, contains(Platform.environment['USERNAME']!));
          expect(text, isNot(contains('BUILTIN\\Users')), reason: text);
        }
      });
    });

    test('a file from before 2.0.0 is read, and written again in format '
        '2', () async {
      final dir = _tempDir();
      final key = AesGcmCipher.randomBytes(AesGcmCipher.keyLength);
      File(
        '${dir.path}${Platform.pathSeparator}.storage.key',
      ).writeAsBytesSync(key);
      Map<String, String> sealV1(String value) {
        final sealed = const AesGcmCipher().seal(
          key,
          Uint8List.fromList(utf8.encode(value)),
          SealedValue.aadFor('ignored', 1),
        );
        return SealedValue(sealed.nonce, sealed.ciphertext).toJson();
      }

      final s = EncryptedFileStorage(dir);
      s.file.writeAsStringSync(
        jsonEncode({'token': sealV1('abc'), 'v': sealV1('a key named v')}),
      );
      expect(await s.readAll(), {'token': 'abc', 'v': 'a key named v'});
      await s.dispose();
      expect(_fileJson(s)['v'], SealedValue.current);
      expect(await EncryptedFileStorage(dir).readAll(), {
        'token': 'abc',
        'v': 'a key named v',
      });
    });

    test('wipe deletes the key: a copy of the old file stays sealed', () async {
      final s = EncryptedFileStorage(_tempDir());
      await s.write('token', 'abc');
      final copy = s.file.readAsBytesSync();
      await s.wipe();
      expect(s.keyFile.existsSync(), isFalse);
      expect(await s.readAll(), isEmpty);
      await s.write('other', 'x');
      s.file.writeAsBytesSync(copy);
      await expectLater(
        EncryptedFileStorage(s.directory).read('token'),
        throwsA(isA<StorageCorruptException>()),
      );
    });
  });
}
