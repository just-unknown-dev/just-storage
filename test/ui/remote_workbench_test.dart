// The workbench tests again, with the workbench reaching the storages
// through the workbench service as the DevTools extension does: every call,
// reply and event goes through JSON (see LoopbackTransport).
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/src/core/workbench_service.dart';

import '../support/workbench_support.dart';
import 'just_storage_admin_screen_test.dart' as screen;
import 'storage_admin_controller_test.dart' as controller;

void main() {
  remoteWorkbench = true;
  // Changes go out at once: the tests wait for the screen's own delay only.
  setUp(() => WorkbenchService.changeDelay = Duration.zero);
  // Each test's workbench connects anew (its listeners live in that test).
  tearDown(WorkbenchService.reset);
  group('remote controller', controller.main);
  group('remote screen', screen.main);
}
