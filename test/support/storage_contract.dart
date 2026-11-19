// What every JustKeyValueStorage does, on every platform: the tests each
// implementation runs. Only the storage under test differs.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

/// A storage under test: [open] gives a fresh one over an empty place,
/// [reopen] another instance over the same place as the last [open].
typedef StorageFactory = ({
  Future<JustKeyValueStorage> Function() open,
  Future<JustKeyValueStorage> Function() reopen,
});

/// Runs the contract tests on [factory]'s storages.
void storageContract(StorageFactory Function() factory) {
  late Future<JustKeyValueStorage> Function() open;
  late Future<JustKeyValueStorage> Function() reopen;

  setUp(() {
    final f = factory();
    open = f.open;
    reopen = f.reopen;
  });

  group('reading and writing', () {
    test('a missing key reads as null', () async {
      final s = await open();
      expect(await s.read('missing'), isNull);
      expect(await s.containsKey('missing'), isFalse);
    });

    test('a written value reads back, an empty one too', () async {
      final s = await open();
      await s.write('name', 'Ada');
      await s.write('empty', '');
      await s.write('unicode', 'ß ✓ 日本 🎮');
      expect(await s.read('name'), 'Ada');
      expect(await s.read('empty'), '');
      expect(await s.containsKey('empty'), isTrue);
      expect(await s.read('unicode'), 'ß ✓ 日本 🎮');
    });

    test('a write replaces the value', () async {
      final s = await open();
      await s.write('k', 'one');
      await s.write('k', 'two');
      expect(await s.read('k'), 'two');
    });

    test('delete removes a key, and does nothing for a missing one', () async {
      final s = await open();
      await s.write('k', 'v');
      await s.delete('k');
      await s.delete('never');
      expect(await s.read('k'), isNull);
      expect(await s.containsKey('k'), isFalse);
    });

    test('clear removes every key', () async {
      final s = await open();
      await s.write('a', '1');
      await s.write('b', '2');
      await s.clear();
      expect(await s.readAll(), isEmpty);
    });

    test('readAll is a copy that cannot be changed', () async {
      final s = await open();
      await s.write('a', '1');
      final all = await s.readAll();
      expect(all, {'a': '1'});
      expect(() => all['b'] = '2', throwsUnsupportedError);
      await s.write('c', '3');
      expect(all, {'a': '1'});
    });

    test('values survive a new instance', () async {
      final s = await open();
      await s.write('a', '1');
      await s.write('b', '2');
      await s.delete('b');
      final again = await reopen();
      expect(await again.readAll(), {'a': '1'});
    });

    test('writes made together all land, in order', () async {
      final s = await open();
      await Future.wait([
        for (var i = 0; i < 50; i++) s.write('k$i', 'v$i'),
        s.write('same', 'first'),
        s.write('same', 'last'),
      ]);
      final again = await reopen();
      final all = await again.readAll();
      for (var i = 0; i < 50; i++) {
        expect(all['k$i'], 'v$i');
      }
      expect(all['same'], 'last');
    });
  });

  group('JSON', () {
    test('writeJson and readJson round-trip an object', () async {
      final s = await open();
      await s.writeJson('p', {'name': 'Ada', 'age': 36}, (m) => m);
      final back = await s.readJson('p', (json) => json);
      expect(back, {'name': 'Ada', 'age': 36});
    });

    test('readJson of a missing key is null', () async {
      final s = await open();
      expect(await s.readJson('missing', (json) => json), isNull);
    });

    test('readJson of something not a JSON object throws', () async {
      final s = await open();
      await s.write('text', 'not json');
      await s.write('list', '[1, 2]');
      await expectLater(
        s.readJson('text', (json) => json),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        s.readJson('list', (json) => json),
        throwsA(isA<StorageException>()),
      );
    });

    test('readJson wraps what fromJson throws', () async {
      final s = await open();
      await s.write('p', '{}');
      await expectLater(
        s.readJson<int>('p', (json) => throw StateError('no')),
        throwsA(
          isA<StorageException>().having((e) => e.cause, 'cause', isStateError),
        ),
      );
    });

    test('writeJson of something JSON cannot hold throws, and writes '
        'nothing', () async {
      final s = await open();
      await expectLater(
        s.writeJson('p', Object(), (o) => {'o': o}),
        throwsA(isA<StorageException>()),
      );
      expect(await s.containsKey('p'), isFalse);
    });
  });

  group('watch', () {
    test('starts with the current value, null for none', () async {
      final s = await open();
      await s.write('k', 'v');
      expect(await s.watch('k').first, 'v');
      expect(await s.watch('missing').first, isNull);
    });

    test('follows writes, deletes and clear', () async {
      final s = await open();
      final seen = <String?>[];
      final sub = s.watch('k').listen(seen.add);
      await pumpEventQueue();
      await s.write('k', 'one');
      await s.write('k', 'two');
      await s.delete('k');
      await s.write('k', 'three');
      await s.clear();
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [null, 'one', 'two', null, 'three', null]);
    });

    test('is broadcast: each listener gets its own first value', () async {
      final s = await open();
      await s.write('k', 'a');
      final stream = s.watch('k');
      final first = <String?>[];
      final second = <String?>[];
      final sub1 = stream.listen(first.add);
      await pumpEventQueue();
      await s.write('k', 'b');
      final sub2 = stream.listen(second.add);
      await pumpEventQueue();
      await s.write('k', 'c');
      await pumpEventQueue();
      await sub1.cancel();
      await sub2.cancel();
      expect(stream.isBroadcast, isTrue);
      expect(first, ['a', 'b', 'c']);
      expect(second, ['b', 'c']);
    });

    test('a cancelled listener hears nothing more', () async {
      final s = await open();
      final seen = <String?>[];
      final sub = s.watch('k').listen(seen.add);
      await pumpEventQueue();
      await sub.cancel();
      await s.write('k', 'after');
      await pumpEventQueue();
      expect(seen, [null]);
    });

    test('a write made while the first value is on its way is sent '
        'once', () async {
      final s = await open();
      final seen = <String?>[];
      final sub = s.watch('k').listen(seen.add);
      await s.write('k', 'v');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, 'v');
      expect(seen.where((value) => value == 'v'), hasLength(1));
    });

    test('other keys do not reach a key\'s listeners', () async {
      final s = await open();
      final seen = <String?>[];
      final sub = s.watch('k').listen(seen.add);
      await pumpEventQueue();
      await s.write('other', 'x');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [null]);
    });
  });
}

/// Completes once [stream] has ended.
Future<void> doneOf(Stream<Object?> stream) {
  final done = Completer<void>();
  stream.listen((_) {}, onDone: done.complete, onError: (Object _) {});
  return done.future;
}
