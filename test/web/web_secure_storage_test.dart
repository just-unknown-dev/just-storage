@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/src/core/core.dart';
import 'package:just_storage/src/core/sealed_value.dart';
import 'package:just_storage/src/web/web.dart';
import 'package:just_storage/src/web/web_aes_gcm_cipher.dart';
import 'package:just_storage/src/web/web_key_store.dart';
import 'package:web/web.dart' as web;

import '../support/storage_contract.dart';

web.Storage get _local => web.window.localStorage;

Map<String, dynamic> _item(String key) =>
    jsonDecode(_local.getItem('${WebSecureStorage.prefix}$key')!)
        as Map<String, dynamic>;

void main() {
  setUp(() async {
    await WebKeyStore().delete();
    _local.clear();
  });

  group('WebSecureStorage contract', () {
    storageContract(
      () => (
        open: () async => WebSecureStorage(),
        reopen: () async => WebSecureStorage(),
      ),
    );
  });

  test('keeps no plaintext, and no raw key, in localStorage', () async {
    await WebSecureStorage().write('token', 'super-secret-value');
    for (var i = 0; i < _local.length; i++) {
      final name = _local.key(i)!;
      expect(_local.getItem(name), isNot(contains('super-secret-value')));
    }
    expect(_local.getItem(WebKeyStore.rawKeyEntry), isNull);
    expect(_item('token')['v'], SealedValue.current);
  });

  test('a value moved to another key fails', () async {
    final s = WebSecureStorage();
    await s.write('role', 'user');
    await s.write('name', 'Ada');
    final role = _local.getItem('${WebSecureStorage.prefix}role')!;
    _local.setItem(
      '${WebSecureStorage.prefix}role',
      _local.getItem('${WebSecureStorage.prefix}name')!,
    );
    _local.setItem('${WebSecureStorage.prefix}name', role);
    await expectLater(
      WebSecureStorage().read('role'),
      throwsA(isA<StorageCorruptException>()),
    );
  });

  test('values that cannot be decrypted fail until clear', () async {
    final s = WebSecureStorage();
    await s.write('a', '1');
    _local.setItem('${WebSecureStorage.prefix}b', '{"v":2,"n":"AA","ct":"AA"}');
    final fresh = WebSecureStorage();
    await expectLater(
      fresh.read('a'),
      throwsA(
        isA<StorageCorruptException>().having((e) => e.keys, 'keys', ['b']),
      ),
    );
    await fresh.clear();
    await fresh.write('c', '3');
    expect(await WebSecureStorage().readAll(), {'c': '3'});
  });

  test('a raw key from before 2.0.0 moves to IndexedDB, and its values '
      'are written again in format 2', () async {
    final raw = WebAesGcmCipher.randomBytes(WebAesGcmCipher.keyLength);
    _local.setItem(WebKeyStore.rawKeyEntry, base64.encode(raw));
    final key = await WebAesGcmCipher.importRawKey(raw);
    final sealed = await const WebAesGcmCipher().seal(
      key,
      Uint8List.fromList(utf8.encode('old token')),
      SealedValue.aadFor('token', 1),
    );
    _local.setItem(
      '${WebSecureStorage.prefix}token',
      jsonEncode(SealedValue(sealed.nonce, sealed.ciphertext).toJson()),
    );

    final s = WebSecureStorage();
    expect(await s.read('token'), 'old token');
    await s.dispose();
    expect(_local.getItem(WebKeyStore.rawKeyEntry), isNull);
    expect(_item('token')['v'], SealedValue.current);
    expect(await WebSecureStorage().read('token'), 'old token');
  });

  test('wipe deletes the key: a copy of the old values stays sealed', () async {
    final s = WebSecureStorage();
    await s.write('token', 'abc');
    final copy = _local.getItem('${WebSecureStorage.prefix}token')!;
    await s.wipe();
    await s.write('other', 'x');
    _local.setItem('${WebSecureStorage.prefix}token', copy);
    await expectLater(
      WebSecureStorage().read('token'),
      throwsA(isA<StorageCorruptException>()),
    );
  });

  test('the factory hands out one instance', () async {
    expect(
      identical(await JustStorage.encrypted(), await JustStorage.encrypted()),
      isTrue,
    );
  });
}
