// What the app and a connected workbench send each other comes back as it
// went, through JSON.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/core/admin_types.dart';
import 'package:just_storage/src/core/workbench_wire.dart';

Map<String, Object?> _wire(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  test('changes', () {
    for (final change in [
      const StorageChange('k', 'v'),
      const StorageChange('k', ''),
      const StorageChange('k', null),
      const StorageChange.cleared(),
    ]) {
      expect(decodeChange(_wire(encodeChange(change))), change);
    }
  });

  test('descriptions', () {
    final modified = DateTime(2026, 11, 20, 18, 30, 5, 123);
    final back = decodeDescription(
      _wire(
        encodeDescription(
          StoreDescription(
            medium: 'Encrypted file',
            sizeBytes: 2048,
            modified: modified,
            canWipe: true,
            facts: const [
              StoreFact('Folder', r'C:\app', path: true),
              StoreFact('Format', 'Version 2'),
            ],
          ),
        ),
      ),
    );
    expect(back.medium, 'Encrypted file');
    expect(back.sizeBytes, 2048);
    expect(back.modified, modified);
    expect(back.canWipe, isTrue);
    expect(
      [for (final f in back.facts) (f.label, f.value, f.path)],
      [('Folder', r'C:\app', true), ('Format', 'Version 2', false)],
    );

    final bare = decodeDescription(
      _wire(encodeDescription(const StoreDescription(medium: 'Browser'))),
    );
    expect(bare.sizeBytes, isNull);
    expect(bare.modified, isNull);
    expect(bare.facts, isEmpty);
  });

  test('storages', () {
    final back = WorkbenchStoreInfo.fromJson(
      _wire(
        const WorkbenchStoreInfo(
          name: 'Secure',
          description: 'JustStorage.encrypted(): AES-256-GCM',
          secure: true,
          canWipe: true,
          type: 'EncryptedFileStorage',
        ).toJson(),
      ),
    );
    expect(
      (back.name, back.description, back.secure, back.canWipe, back.type),
      (
        'Secure',
        'JustStorage.encrypted(): AES-256-GCM',
        true,
        true,
        'EncryptedFileStorage',
      ),
    );
  });

  group('errors keep their kind and what they say', () {
    Object roundTrip(Object error) => decodeError(_wire(encodeError(error)));

    test('a storage that can\'t be read', () {
      final back = roundTrip(
        const StorageCorruptException(
          '/data/just_secure_storage.enc',
          'none of its values can be decrypted.',
          keys: ['a', 'b'],
          cause: FormatException('bad tag'),
        ),
      );
      expect(back, isA<StorageCorruptException>());
      back as StorageCorruptException;
      expect(back.source, '/data/just_secure_storage.enc');
      expect(back.message, 'none of its values can be decrypted.');
      expect(back.keys, ['a', 'b']);
      expect('${back.cause}', 'FormatException: bad tag');
    });

    test('other kinds', () {
      final storage = roundTrip(const StorageException('disk full'));
      expect(storage, isA<StorageException>());
      expect((storage as StorageException).cause, isNull);
      expect(roundTrip(StateError('taken')), isA<StateError>());
      expect(roundTrip(ArgumentError('no key')), isA<ArgumentError>());
      expect(roundTrip(const FormatException('x')), isA<FormatException>());
      expect(roundTrip(UnsupportedError('no')), isA<UnsupportedError>());
      final other = roundTrip(Exception('odd'));
      expect(other, isA<WorkbenchRemoteError>());
      expect('$other', 'Exception: odd');
    });
  });
}
