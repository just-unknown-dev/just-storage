import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

void main() {
  test('StorageException says what went wrong, and why', () {
    expect(
      const StorageException('disk full').toString(),
      'StorageException: disk full',
    );
    expect(
      const StorageException('disk full', cause: 'ENOSPC').toString(),
      'StorageException: disk full (caused by: ENOSPC)',
    );
  });

  test('StorageCorruptException names where, and which keys', () {
    const e = StorageCorruptException(
      '/data/x.enc',
      'some values can\'t be decrypted.',
      keys: ['a', 'b'],
    );
    expect(e, isA<StorageException>());
    expect(e.source, '/data/x.enc');
    expect(
      e.toString(),
      'StorageCorruptException: /data/x.enc: some values can\'t be '
      'decrypted. (keys: a, b)',
    );
  });
}
