import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final List<Directory> _tempDirs = [];

Future<FileStorage> _buildStandard([
  Map<String, String> initial = const {},
]) async {
  final dir = await Directory.systemTemp.createTemp('jst_');
  _tempDirs.add(dir);
  final storage = FileStorage(dir);
  for (final entry in initial.entries) {
    await storage.write(entry.key, entry.value);
  }
  return storage;
}

Future<EncryptedFileStorage> _buildSecure([
  Map<String, String> initial = const {},
]) async {
  final dir = await Directory.systemTemp.createTemp('est_');
  _tempDirs.add(dir);
  final storage = EncryptedFileStorage(dir);
  for (final entry in initial.entries) {
    await storage.write(entry.key, entry.value);
  }
  return storage;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  tearDown(() async {
    for (final dir in List<Directory>.from(_tempDirs)) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    _tempDirs.clear();
  });

  // ------------------------------------------------------------------
  // StorageException
  // ------------------------------------------------------------------
  group('StorageException', () {
    test('toString without cause', () {
      const e = StorageException('boom');
      expect(e.toString(), 'StorageException: boom');
    });

    test('toString with cause', () {
      const e = StorageException('boom', cause: 'root');
      expect(e.toString(), contains('caused by: root'));
    });
  });

  // ------------------------------------------------------------------
  // FileStorage (standard)
  // ------------------------------------------------------------------
  group('FileStorage', () {
    test('read returns null for missing key', () async {
      final s = await _buildStandard();
      expect(await s.read('missing'), isNull);
    });

    test('write then read round-trips', () async {
      final s = await _buildStandard();
      await s.write('k', 'v');
      expect(await s.read('k'), 'v');
    });

    test('delete removes key', () async {
      final s = await _buildStandard({'k': 'v'});
      await s.delete('k');
      expect(await s.read('k'), isNull);
    });

    test('containsKey reflects presence', () async {
      final s = await _buildStandard({'k': 'v'});
      expect(await s.containsKey('k'), isTrue);
      expect(await s.containsKey('nope'), isFalse);
    });

    test('clear removes all keys', () async {
      final s = await _buildStandard({'a': '1', 'b': '2'});
      await s.clear();
      expect(await s.read('a'), isNull);
      expect(await s.read('b'), isNull);
    });

    test('writeJson / readJson round-trips a map', () async {
      final s = await _buildStandard();
      await s.writeJson<Map<String, dynamic>>(
        'obj',
        {'name': 'Alice', 'score': 42},
        (v) => v,
      );
      final result = await s.readJson<Map<String, dynamic>>(
        'obj',
        (j) => j,
      );
      expect(result, {'name': 'Alice', 'score': 42});
    });

    test('readJson returns null for missing key', () async {
      final s = await _buildStandard();
      expect(
        await s.readJson<Map<String, dynamic>>('missing', (j) => j),
        isNull,
      );
    });

    test('data persists across re-opens of the same directory', () async {
      final dir = await Directory.systemTemp.createTemp('persist_');
      _tempDirs.add(dir);

      final s1 = FileStorage(dir);
      await s1.write('x', '42');

      final s2 = FileStorage(dir);
      expect(await s2.read('x'), '42');
    });

    test('watch emits current value immediately', () async {
      final s = await _buildStandard({'x': 'initial'});
      expect(await s.watch('x').first, 'initial');
    });

    test('watch emits null when key is absent', () async {
      final s = await _buildStandard();
      expect(await s.watch('absent').first, isNull);
    });

    test('watch emits new value after write', () async {
      final s = await _buildStandard();
      final emissions = <String?>[];

      final sub = s.watch('y').listen(emissions.add);
      await s.write('y', 'hello');
      await s.write('y', 'world');
      await sub.cancel();

      expect(emissions, [null, 'hello', 'world']);
    });

    test('watch emits null after delete', () async {
      final s = await _buildStandard({'z': 'val'});
      final emissions = <String?>[];

      final sub = s.watch('z').listen(emissions.add);
      await s.delete('z');
      await sub.cancel();

      expect(emissions, ['val', null]);
    });

    test('watch emits null after clear', () async {
      final s = await _buildStandard({'a': '1'});
      final emissions = <String?>[];

      final sub = s.watch('a').listen(emissions.add);
      await s.clear();
      await sub.cancel();

      expect(emissions, ['1', null]);
    });
  });

  // ------------------------------------------------------------------
  // EncryptedFileStorage (secure)
  // ------------------------------------------------------------------
  group('EncryptedFileStorage', () {
    test('read returns null for missing key', () async {
      final s = await _buildSecure();
      expect(await s.read('missing'), isNull);
    });

    test('write then read round-trips', () async {
      final s = await _buildSecure();
      await s.write('token', 'abc123');
      expect(await s.read('token'), 'abc123');
    });

    test('delete removes key', () async {
      final s = await _buildSecure({'token': 'abc'});
      await s.delete('token');
      expect(await s.read('token'), isNull);
    });

    test('containsKey reflects presence', () async {
      final s = await _buildSecure({'k': 'v'});
      expect(await s.containsKey('k'), isTrue);
      expect(await s.containsKey('nope'), isFalse);
    });

    test('clear removes all keys', () async {
      final s = await _buildSecure({'a': '1', 'b': '2'});
      await s.clear();
      expect(await s.read('a'), isNull);
      expect(await s.read('b'), isNull);
    });

    test('readAll returns all entries', () async {
      final s = await _buildSecure({'a': '1', 'b': '2'});
      final all = await s.readAll();
      expect(all, {'a': '1', 'b': '2'});
    });

    test('writeJson / readJson round-trips a map', () async {
      final s = await _buildSecure();
      await s.writeJson<Map<String, dynamic>>(
        'user',
        {'id': '42', 'email': 'alice@example.com'},
        (v) => v,
      );
      final result = await s.readJson<Map<String, dynamic>>(
        'user',
        (j) => j,
      );
      expect(result, {'id': '42', 'email': 'alice@example.com'});
    });

    test('readJson returns null for missing key', () async {
      final s = await _buildSecure();
      expect(
        await s.readJson<Map<String, dynamic>>('missing', (j) => j),
        isNull,
      );
    });

    test('data persists and decrypts correctly across re-opens', () async {
      final dir = await Directory.systemTemp.createTemp('enc_persist_');
      _tempDirs.add(dir);

      final s1 = EncryptedFileStorage(dir);
      await s1.write('secret', 'p@ssw0rd');

      final s2 = EncryptedFileStorage(dir);
      expect(await s2.read('secret'), 'p@ssw0rd');
    });

    test('each write uses a distinct nonce (ciphertext differs)', () async {
      final dir = await Directory.systemTemp.createTemp('nonce_');
      _tempDirs.add(dir);

      final s = EncryptedFileStorage(dir);
      await s.write('k', 'same-value');
      final enc1 = await File(
        '${dir.path}${Platform.pathSeparator}just_secure_storage.enc',
      ).readAsString();

      // Force a fresh instance so _initFuture is reset, triggering a new flush
      final s2 = EncryptedFileStorage(dir);
      await s2.write('k', 'same-value');
      final enc2 = await File(
        '${dir.path}${Platform.pathSeparator}just_secure_storage.enc',
      ).readAsString();

      // Even though the plaintext is identical, ciphertexts must differ
      // because each write generates a fresh random nonce.
      expect(enc1, isNot(equals(enc2)));
    });

    test('tampering with the ciphertext is detected', () async {
      final dir = await Directory.systemTemp.createTemp('tamper_');
      _tempDirs.add(dir);

      final s1 = EncryptedFileStorage(dir);
      await s1.write('k', 'sensitive');

      // Corrupt a byte in the middle of the encrypted file.
      final encFile = File(
        '${dir.path}${Platform.pathSeparator}just_secure_storage.enc',
      );
      final raw = await encFile.readAsString();
      // Replace a character in the ciphertext portion (after the first 20).
      final corrupted = raw.replaceRange(30, 31, raw[30] == 'A' ? 'B' : 'A');
      await encFile.writeAsString(corrupted);

      final s2 = EncryptedFileStorage(dir);
      expect(
        () => s2.read('k'),
        throwsA(isA<StorageException>()),
      );
    });

    test('watch emits current value immediately', () async {
      final s = await _buildSecure({'t': 'tok'});
      expect(await s.watch('t').first, 'tok');
    });

    test('watch emits null when key is absent', () async {
      final s = await _buildSecure();
      expect(await s.watch('absent').first, isNull);
    });

    test('watch emits new value after write', () async {
      final s = await _buildSecure();
      final emissions = <String?>[];

      final sub = s.watch('tok').listen(emissions.add);
      await s.write('tok', 'v1');
      await s.write('tok', 'v2');
      await sub.cancel();

      expect(emissions, [null, 'v1', 'v2']);
    });

    test('watch emits null after delete', () async {
      final s = await _buildSecure({'k': 'secret'});
      final emissions = <String?>[];

      final sub = s.watch('k').listen(emissions.add);
      await s.delete('k');
      await sub.cancel();

      expect(emissions, ['secret', null]);
    });

    test('watch emits null after clear', () async {
      final s = await _buildSecure({'k': 'secret', 'k2': 'other'});
      final emissions = <String?>[];

      final sub = s.watch('k').listen(emissions.add);
      await s.clear();
      await sub.cancel();

      expect(emissions, ['secret', null]);
    });
  });
}
