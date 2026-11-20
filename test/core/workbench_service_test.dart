// The workbench service, as the DevTools extension reaches it: what the app
// shows, the calls on its storages, errors as the app saw them, and the
// change events — gathered, and sent only while a workbench is connected.
// The last test goes through the real Dart VM service.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as isolates;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/core/workbench_service.dart';
import 'package:just_storage/src/core/workbench_wire.dart';
import 'package:just_storage/src/ui/backend/remote_storage.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../support/memory_storage.dart';
import '../support/workbench_support.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('jst_wb_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String _folder(Directory dir) =>
    dir.absolute.uri.pathSegments.where((s) => s.isNotEmpty).last;

/// The events posted from now on, with their data.
List<(String, Map<String, Object?>)> _record() {
  final seen = <(String, Map<String, Object?>)>[];
  final sub = WorkbenchService.events.listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}

List<Object?> _changesIn(List<(String, Map<String, Object?>)> events) => [
  for (final (kind, data) in events)
    if (kind == workbenchChangeEvent) data['changes'],
];

void main() {
  tearDown(WorkbenchService.reset);

  group('what is shown', () {
    test('the storages JustStorage opens, named after their folder', () async {
      final dir = _tempDir();
      await JustStorage.standard(dir);
      await JustStorage.standard(dir);
      await JustStorage.encrypted(dir);
      expect(WorkbenchService.storeNames, [
        'Standard (${_folder(dir)})',
        'Secure (${_folder(dir)})',
      ]);

      final host = RemoteStorageHost(LoopbackTransport());
      addTearDown(host.dispose);
      final stores = await host.listStores();
      expect([for (final s in stores) s.isSecure], [false, true]);
      expect(
        stores.first.description,
        'JustStorage.standard(${dir.path}): '
        'plain values',
      );
    });

    test('none while debugDevToolsWorkbench is false', () async {
      JustStorage.debugDevToolsWorkbench = false;
      addTearDown(() => JustStorage.debugDevToolsWorkbench = true);
      await JustStorage.standard(_tempDir());
      JustStorage.debugShowInDevTools('Mine', MemoryStandardStorage());
      expect(WorkbenchService.storeNames, isEmpty);
    });

    test('debugShowInDevTools replaces a name, and renames a storage', () {
      final a = MemoryStandardStorage();
      final b = MemoryStandardStorage();
      JustStorage.debugShowInDevTools('A', a);
      JustStorage.debugShowInDevTools('B', b);
      JustStorage.debugShowInDevTools('A', b);
      expect(WorkbenchService.storeNames, ['A']);
      JustStorage.debugShowInDevTools('C', b);
      expect(WorkbenchService.storeNames, ['C']);
    });

    test('a second storage of a name is numbered', () {
      for (var i = 0; i < 3; i++) {
        WorkbenchService.track(
          MemoryStandardStorage(),
          name: 'Saves',
          platform: testPlatform,
        );
      }
      expect(WorkbenchService.storeNames, ['Saves', 'Saves 2', 'Saves 3']);
    });
  });

  test(
    'the calls reach the storage, and errors come back as they were',
    () async {
      final memory = MemorySecureStorage()..values['a'] = '1';
      final remote = _remote('Memory', memory);

      expect(await remote.readAll(), {'a': '1'});
      await remote.write('b', '2');
      expect(memory.values, {'a': '1', 'b': '2'});
      expect(await remote.read('b'), '2');
      expect(await remote.read('nope'), isNull);
      expect(await remote.containsKey('a'), isTrue);
      await remote.delete('a');
      expect(memory.values, {'b': '2'});
      await remote.clear();
      expect(memory.values, isEmpty);

      memory.failure = const StorageCorruptException(
        'secure.enc',
        'none of its values can be decrypted.',
        keys: ['x', 'y'],
        cause: FormatException('bad tag'),
      );
      final error = await remote.readAll().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(error, isA<StorageCorruptException>());
      error as StorageCorruptException;
      expect(error.source, 'secure.enc');
      expect(error.message, 'none of its values can be decrypted.');
      expect(error.keys, ['x', 'y']);
      expect('${error.cause}', contains('bad tag'));
    },
  );

  test(
    'a file storage says where it keeps its values; wipe asks first',
    () async {
      final dir = _tempDir();
      final standard = await JustStorage.standard(dir);
      await standard.write('k', 'v');
      final host = RemoteStorageHost(LoopbackTransport());
      addTearDown(host.dispose);
      final store = (await host.listStores()).single;
      final remote = host.storageNamed(store.name)!;
      final description = await remote.describe();
      expect(description?.medium, 'JSON file');
      expect(description?.sizeBytes, greaterThan(0));
      expect(
        description?.facts.where((f) => f.path).map((f) => f.value),
        contains(dir.path),
      );
      expect(remote.info.canWipe, isFalse);
      await expectLater(remote.wipe(), throwsA(isA<StateError>()));
    },
  );

  test('changes are gathered: one event per delay, each key once with its '
      'last value', () async {
    final memory = MemoryStandardStorage();
    final remote = _remote('Memory', memory);
    await remote.readAll(); // connects
    final events = _record();
    await memory.write('a', '1');
    await memory.write('a', '2');
    await memory.write('b', 'x');
    await memory.delete('b');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(_changesIn(events), [
      [
        {'key': 'a', 'value': '2'},
        {'key': 'b', 'value': null},
      ],
    ]);

    events.clear();
    await memory.write('gone', '1');
    await memory.clear();
    await memory.write('c', '3');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(_changesIn(events), [
      [
        {'clear': true},
        {'key': 'c', 'value': '3'},
      ],
    ]);
  });

  test(
    'a remote storage reports the changes, and watch follows a key',
    () async {
      // Each change on its own (gathering is tested above).
      WorkbenchService.changeDelay = Duration.zero;
      final memory = MemoryStandardStorage()..values['k'] = 'first';
      final remote = _remote('Memory', memory);
      final changes = <StorageChange>[];
      final values = <String?>[];
      final subs = [
        remote.changes.listen(changes.add),
        remote.watch('k').listen(values.add),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await memory.write('k', 'second');
      await memory.write('other', 'x');
      await memory.clear();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(values, ['first', 'second', null]);
      expect(changes, [
        const StorageChange('k', 'second'),
        const StorageChange('other', 'x'),
        const StorageChange.cleared(),
      ]);
    },
  );

  test('a storage shown while a workbench is connected is announced', () async {
    final host = RemoteStorageHost(LoopbackTransport());
    addTearDown(host.dispose);
    expect(await host.listStores(), isEmpty);
    var told = 0;
    final sub = host.storesChanged.listen((_) => told++);
    addTearDown(sub.cancel);
    WorkbenchService.track(
      MemoryStandardStorage(),
      name: 'Late',
      platform: testPlatform,
    );
    await Future<void>.delayed(Duration.zero);
    expect(told, 1);
    expect([for (final s in await host.listStores()) s.name], ['Late']);
  });

  test('no events once the last workbench disconnects', () async {
    final memory = MemoryStandardStorage();
    WorkbenchService.show('Memory', memory, platform: testPlatform);
    final first = RemoteStorageHost(LoopbackTransport());
    final second = RemoteStorageHost(LoopbackTransport());
    await first.listStores();
    await second.listStores();
    final events = _record();

    first.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await memory.write('a', '1');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(_changesIn(events), hasLength(1), reason: 'one is still connected');

    second.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await memory.write('a', '2');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(_changesIn(events), hasLength(1), reason: 'nobody is connected');
  });

  test('the version the app tells is the package\'s', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(justStorageVersion, version);
  });

  test('the console note is a box with the link on a line of its own', () {
    const link = 'http://127.0.0.1:1234/abc=/devtools/just_storage_ext?uri=x';
    final lines = WorkbenchService.workbenchBanner(link).split('\n');
    expect(lines.map((l) => l.length).toSet(), hasLength(1));
    expect(lines.where((l) => l.contains(link)), hasLength(1));
    expect(lines[1], contains('Just Storage workbench'));
  });

  test('a client calls the service over the VM service and gets its '
      'events while connected', () async {
    final dir = _tempDir();
    final storage = await JustStorage.standard(dir);

    final info = await developer.Service.getInfo();
    if (info.serverUri == null) {
      markTestSkipped('needs the VM service: flutter test --enable-vmservice');
      return;
    }
    final service = await vmServiceConnectUri('${info.serverWebSocketUri}');
    addTearDown(service.dispose);
    final isolateId = developer.Service.getIsolateId(isolates.Isolate.current)!;
    final isolate = await service.getIsolate(isolateId);
    expect(
      isolate.extensionRPCs,
      contains(workbenchExtension),
      reason: 'opening a storage registers the service in a debug build',
    );

    Future<Map<String, Object?>> call(
      String method, [
      Map<String, Object?> args = const {},
    ]) async {
      final response = await service.callServiceExtension(
        workbenchExtension,
        isolateId: isolateId,
        args: {'method': method, 'args': jsonEncode(args)},
      );
      return response.json!.cast<String, Object?>();
    }

    await service.streamListen(EventStreams.kExtension);
    final kinds = <String>[];
    final sub = service.onExtensionEvent.listen((e) {
      if (e.extensionKind case final kind?) kinds.add(kind);
    });
    addTearDown(sub.cancel);

    await storage.write('before', '1');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      kinds,
      isEmpty,
      reason: 'nothing is sent before a workbench connects',
    );

    final hello = await call('connect');
    expect(hello['ok'], isTrue);
    expect(hello['protocol'], workbenchProtocol);
    final session = hello['session'];
    final name = 'Standard (${_folder(dir)})';
    final list = await call('list', {'session': session});
    expect(
      [for (final s in list['stores'] as List) (s as Map)['name']],
      [name],
    );
    expect(await call('write', {'store': name, 'key': 'k', 'value': 'v'}), {
      'ok': true,
    });
    expect(await storage.read('k'), 'v');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(kinds, contains(workbenchChangeEvent));

    await call('disconnect', {'session': session});
    kinds.clear();
    await storage.write('after', '1');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(kinds, isEmpty, reason: 'nothing is sent once it disconnects');
  });
}

/// [storage] shown as [name], and the remote storage a connected workbench
/// gets for it.
RemoteStorage _remote(String name, JustKeyValueStorage storage) {
  WorkbenchService.show(name, storage, platform: testPlatform);
  final host = RemoteStorageHost(LoopbackTransport());
  addTearDown(host.dispose);
  host.storeOf(
    WorkbenchStoreInfo(
      name: name,
      secure: storage is JustSecureStorage,
      canWipe: false,
      type: '${storage.runtimeType}',
    ),
  );
  return host.storageNamed(name)!;
}
