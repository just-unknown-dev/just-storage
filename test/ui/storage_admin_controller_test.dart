import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/ui/admin_utils.dart';
import 'package:just_storage/ui.dart';

import '../support/memory_storage.dart';
import '../support/workbench_support.dart';

void main() {
  late MemoryStandardStorage memory;
  late StorageAdminStore store;
  late StorageAdminController controller;

  setUp(() async {
    memory = MemoryStandardStorage()..values.addAll({'a': '1', 'b': '2'});
    store = adminStore('Memory', memory);
    controller = StorageAdminController(stores: [store]);
    await controller.refresh();
  });

  tearDown(() => controller.dispose());

  test('reads every storage, and knows a secure one', () {
    expect(controller.entriesOf(store), {'a': '1', 'b': '2'});
    expect(controller.isLoaded(store), isTrue);
    expect(controller.errorOf(store), isNull);
    expect(controller.selectedStore, store);
    expect(store.isSecure, isFalse);
    expect(StorageAdminStore('S', MemorySecureStorage()).isSecure, isTrue);
    expect(StorageAdminStore.secure().isSecure, isTrue);
  });

  test('two storages of one name are refused', () {
    expect(
      () => StorageAdminController(
        stores: [
          StorageAdminStore('x', MemoryStandardStorage()),
          StorageAdminStore('x', MemoryStandardStorage()),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rename moves a value and follows the selection', () async {
    controller.select(store, key: 'a');
    await controller.rename(store, 'a', 'z');
    expect(memory.values, {'z': '1', 'b': '2'});
    expect(controller.selectedKey, 'z');
    expect(controller.entriesOf(store), {'z': '1', 'b': '2'});
  });

  test('rename and copy never replace a value', () async {
    await expectLater(
      controller.rename(store, 'a', 'b'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      controller.copy(store, 'a', 'b'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      controller.rename(store, 'missing', 'new'),
      throwsA(isA<StateError>()),
    );
    expect(memory.values, {'a': '1', 'b': '2'});
  });

  test('delete removes several keys, and the selection with them', () async {
    controller.select(store, key: 'a');
    await controller.delete(store, ['a', 'b']);
    expect(memory.values, isEmpty);
    expect(controller.selectedKey, isNull);
  });

  test('import merges, adds only new keys, or replaces all', () async {
    expect(await controller.importEntries(store, {'a': 'A', 'c': 'C'}), 2);
    expect(memory.values, {'a': 'A', 'b': '2', 'c': 'C'});

    expect(
      await controller.importEntries(store, {
        'a': 'again',
        'd': 'D',
      }, replaceExisting: false),
      1,
    );
    expect(memory.values, {'a': 'A', 'b': '2', 'c': 'C', 'd': 'D'});

    expect(
      await controller.importEntries(store, {'only': 'me'}, clearFirst: true),
      1,
    );
    expect(memory.values, {'only': 'me'});
  });

  test('an export imports back into another storage', () async {
    final json = controller.exportJson(store, keys: ['b', 'missing']);
    final data = parseImport(json);
    expect(data.entries, {'b': '2'});
    expect(data.store, 'Memory');
  });

  test('a read-only controller changes nothing', () async {
    final readOnly = StorageAdminController(stores: [store], readOnly: true);
    addTearDown(readOnly.dispose);
    await readOnly.refresh();
    for (final change in <Future<void> Function()>[
      () => readOnly.write(store, 'k', 'v'),
      () => readOnly.delete(store, ['a']),
      () => readOnly.rename(store, 'a', 'x'),
      () => readOnly.copy(store, 'a', 'x'),
      () => readOnly.clear(store),
      () => readOnly.importEntries(store, {'k': 'v'}),
    ]) {
      await expectLater(change(), throwsA(isA<StateError>()));
    }
    expect(memory.values, {'a': '1', 'b': '2'});
    expect(readOnly.exportJson(store), contains('"a"'));
  });

  testWidgets('follows changes made elsewhere, and marks them for a moment', (
    tester,
  ) async {
    // A store of the test's own, so a remote one hears changes in the
    // test's zone.
    final watched = adminStore('Memory', memory);
    final live = StorageAdminController(stores: [watched]);
    await live.refresh();
    var told = 0;
    live.addListener(() => told++);
    memory.changeBehindItsBack('new', 'value');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(live.entriesOf(watched)['new'], 'value');
    expect(live.changedAt(watched, 'new'), isNotNull);
    expect(told, greaterThan(0));
    await tester.pump(StorageAdminController.recentChange);
    expect(live.changedAt(watched, 'new'), isNull);
    live.dispose();
  });

  test('a storage that fails to open is an error, and opens later', () async {
    var fail = true;
    final flaky = adminStore('Flaky', _FailingOnce(() => fail));
    final c = StorageAdminController(stores: [flaky]);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.errorOf(flaky), isA<StorageException>());
    fail = false;
    await c.refresh();
    expect(c.errorOf(flaky), isNull);
  });

  test(
    'a new list of storages keeps what it knew of those that stay',
    () async {
      final other = adminStore(
        'Other',
        MemoryStandardStorage()..values['x'] = 'y',
      );
      controller.select(store, key: 'a');
      controller.setStores([other, store]);
      expect(controller.stores, [other, store]);
      expect(controller.entriesOf(store), {'a': '1', 'b': '2'});
      expect(controller.selectedStore, store);
      expect(controller.selectedKey, 'a');
      await controller.refresh(other);
      expect(controller.entriesOf(other), {'x': 'y'});

      controller.setStores([other]);
      expect(controller.selectedStore, other);
      expect(controller.selectedKey, isNull);
      expect(() => controller.entriesOf(store), throwsArgumentError);
      expect(
        () => controller.setStores([other, adminStore('Other', memory)]),
        throwsArgumentError,
      );
    },
  );

  test('wipe is offered only where the storage can be wiped', () {
    expect(controller.canWipe(store), isFalse);
    expect(controller.wipe(store), throwsA(isA<StateError>()));
  });

  test('the appearance is dark unless given, and a change notifies', () {
    expect(controller.themeMode, ThemeMode.dark);
    var notified = 0;
    controller.addListener(() => notified++);
    controller
      ..setThemeMode(ThemeMode.light)
      ..setThemeMode(ThemeMode.light);
    expect(controller.themeMode, ThemeMode.light);
    expect(notified, 1);

    final system = StorageAdminController(
      stores: [store],
      themeMode: ThemeMode.system,
    );
    addTearDown(system.dispose);
    expect(system.themeMode, ThemeMode.system);
  });
}

/// A storage whose reads fail while [failing] says so.
class _FailingOnce extends MemoryStandardStorage {
  _FailingOnce(this.failing);

  final bool Function() failing;

  @override
  Future<Map<String, String>> readAll() async {
    if (failing()) throw const StorageException('not now');
    return super.readAll();
  }
}
