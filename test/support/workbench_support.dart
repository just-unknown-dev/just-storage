// The workbench as the DevTools extension reaches the app: through the
// workbench service, with every call, reply and event going through JSON.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/src/core/admin_types.dart';
import 'package:just_storage/src/core/workbench_service.dart';
import 'package:just_storage/src/core/workbench_wire.dart';
import 'package:just_storage/src/ui/backend/remote_storage.dart';
import 'package:just_storage/ui.dart';

/// Whether [adminStore] hands the screen the storage as a connected
/// workbench reaches it (test/ui/remote_workbench_test.dart).
bool remoteWorkbench = false;

/// [storage] shown as [name]: as it is, or — with [remoteWorkbench] —
/// shown by the workbench service and reached through a
/// [RemoteStorageHost] of its own over [LoopbackTransport], so its events
/// arrive in the zone of the test that asked for it.
StorageAdminStore adminStore(
  String name,
  JustKeyValueStorage storage, {
  String? description,
}) {
  if (!remoteWorkbench) {
    return StorageAdminStore(name, storage, description: description);
  }
  WorkbenchService.show(
    name,
    storage,
    description: description,
    platform: testPlatform,
  );
  final host = RemoteStorageHost(LoopbackTransport());
  addTearDown(host.dispose);
  return host.storeOf(
    WorkbenchStoreInfo(
      name: name,
      description: description,
      secure: storage is JustSecureStorage,
      canWipe: false,
      type: '${storage.runtimeType}',
    ),
  );
}

/// What the platform says of a test storage: nothing about where it keeps
/// its values, and it can't be wiped.
const StoragePlatformAdmin testPlatform = (
  describe: _describe,
  canWipe: _canWipe,
  wipe: _wipe,
);

Future<StoreDescription?> _describe(JustKeyValueStorage _) async => null;

bool _canWipe(JustKeyValueStorage _) => false;

Future<void> _wipe(JustKeyValueStorage _) =>
    Future.error(UnsupportedError('a test storage can\'t be wiped'));

/// Reaches [WorkbenchService] in this isolate as the DevTools extension
/// reaches it in the app's: every call, reply and event through JSON.
final class LoopbackTransport implements WorkbenchTransport {
  static Map<String, Object?> _wire(Map<String, Object?> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, Object?>;

  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> args,
  ) async => _wire(await WorkbenchService.handle(method, _wire(args)));

  @override
  Stream<(String, Map<String, Object?>)> get events =>
      WorkbenchService.events.map((e) => (e.$1, _wire(e.$2)));
}
