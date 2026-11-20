// The just_storage workbench as a Flutter DevTools extension: the screen
// the app can show itself (JustStorageAdminScreen), on the storages of the
// app DevTools is connected to. It reaches them through the workbench
// service just_storage registers in debug builds.
//
// Built into ../extension/devtools/build (see README.md); not published.

// The remote side of the workbench is internal to just_storage, and this
// app is built and shipped with it.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:just_storage/src/core/workbench_wire.dart';
import 'package:just_storage/src/ui/backend/remote_storage.dart';
import 'package:just_storage/ui.dart';
import 'package:vm_service/vm_service.dart';

void main() => runApp(const DevToolsExtension(child: WorkbenchExtension()));

/// Waits for the connected app's workbench service, then shows the
/// workbench on its storages; starts over when the app restarts.
class WorkbenchExtension extends StatefulWidget {
  const WorkbenchExtension({super.key});

  @override
  State<WorkbenchExtension> createState() => _WorkbenchExtensionState();
}

class _WorkbenchExtensionState extends State<WorkbenchExtension> {
  RemoteStorageHost? _host;
  StorageAdminController? _controller;
  StreamSubscription<void>? _listSub;
  IsolateRef? _isolate;
  Object? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    serviceManager.isolateManager.mainIsolate.addListener(_restart);
    serviceManager.connectedState.addListener(_restart);
    _restart();
  }

  @override
  void dispose() {
    serviceManager.isolateManager.mainIsolate.removeListener(_restart);
    serviceManager.connectedState.removeListener(_restart);
    _drop();
    super.dispose();
  }

  /// Lets go of the workbench of the previous app (or run).
  void _drop() {
    unawaited(_listSub?.cancel());
    _listSub = null;
    _controller?.dispose();
    _controller = null;
    _host?.dispose();
    _host = null;
  }

  /// Drops the workbench of the previous app (or run) and waits for the
  /// service of the current one.
  void _restart() {
    final isolate = serviceManager.connectedState.value.connected
        ? serviceManager.isolateManager.mainIsolate.value
        : null;
    if (isolate?.id == _isolate?.id &&
        (_controller != null || _error != null || isolate == null)) {
      return;
    }
    _isolate = isolate;
    _drop();
    _error = null;
    final attempt = ++_attempt;
    if (mounted) setState(() {});
    if (isolate == null) return;
    unawaited(
      serviceManager.serviceExtensionManager
          .waitForServiceExtensionAvailable(workbenchExtension)
          .then((_) => _open(attempt)),
    );
  }

  Future<void> _open(int attempt) async {
    if (!mounted || attempt != _attempt) return;
    final host = RemoteStorageHost(_DevToolsTransport());
    try {
      final stores = await host.listStores();
      if (!mounted || attempt != _attempt) {
        host.dispose();
        return;
      }
      final controller = StorageAdminController(stores: stores);
      _listSub = host.storesChanged.listen((_) async {
        try {
          final next = await host.listStores();
          if (identical(_controller, controller)) controller.setStores(next);
        } catch (_) {
          // The app went away; _restart follows.
        }
      });
      setState(() {
        _host = host;
        _controller = controller;
      });
    } catch (e) {
      host.dispose();
      if (mounted && attempt == _attempt) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return JustStorageAdminScreen(
        key: ObjectKey(controller),
        controller: controller,
        title: 'Just Storage',
      );
    }
    final connected = serviceManager.connectedState.value.connected;
    final error = _error;
    return _Waiting(
      title: error != null
          ? 'Could not reach the app\'s storages'
          : connected
          ? 'Waiting for the app'
          : 'No app connected',
      message: error != null
          ? '$error'
          : connected
          ? 'The workbench appears once the app opens a storage in a debug '
                'build (JustStorage.standard or JustStorage.encrypted, or '
                'one given to JustStorage.debugShowInDevTools). It is off '
                'when the app sets JustStorage.debugDevToolsWorkbench to '
                'false.'
          : 'Run your app in debug mode and connect DevTools to it.',
    );
  }
}

/// Calls the app's workbench service through DevTools' VM service
/// connection.
final class _DevToolsTransport implements WorkbenchTransport {
  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> args,
  ) async {
    final response = await serviceManager.callServiceExtensionOnMainIsolate(
      workbenchExtension,
      args: {'method': method, 'args': jsonEncode(args)},
    );
    return {...?response.json}.cast<String, Object?>();
  }

  @override
  Stream<(String, Map<String, Object?>)> get events {
    final service = serviceManager.service;
    if (service == null) return const Stream.empty();
    return service.onExtensionEvent
        .where(
          (e) => e.extensionKind?.startsWith(workbenchEventPrefix) ?? false,
        )
        .map(
          (e) => (
            e.extensionKind!,
            {...?e.extensionData?.data}.cast<String, Object?>(),
          ),
        );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
