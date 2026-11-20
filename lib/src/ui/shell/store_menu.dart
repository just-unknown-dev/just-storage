/// The actions on a whole storage, as one menu for the sidebar, the
/// workspace header and the phone page.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../dialogs/entry_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';

/// What can be done to a whole storage.
@internal
enum StoreAction {
  /// Read it again.
  refresh,

  /// Add an entry.
  add,

  /// Export its entries.
  export,

  /// Import entries into it.
  import,

  /// Remove every entry.
  clear,

  /// Remove every entry and destroy the key.
  wipe,
}

/// The menu entries for [store], [StoreAction.add] among them when [withAdd].
@internal
List<PopupMenuEntry<StoreAction>> storeMenuItems(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store, {
  bool withAdd = false,
}) {
  final error = controller.errorOf(store);
  final unreadable = error is StorageCorruptException;
  final count = controller.entriesOf(store).length;
  final writable = !controller.readOnly;
  return [
    menuItem(context, StoreAction.refresh, Icons.refresh, 'Read again'),
    if (withAdd && writable)
      menuItem(
        context,
        StoreAction.add,
        Icons.add,
        'Add entry…',
        enabled: error == null,
      ),
    const PopupMenuDivider(),
    menuItem(
      context,
      StoreAction.export,
      Icons.upload_outlined,
      'Export…',
      enabled: error == null && count > 0,
      key: const ValueKey('jst-menu-export'),
    ),
    if (writable)
      menuItem(
        context,
        StoreAction.import,
        Icons.download_outlined,
        'Import…',
        enabled: error == null,
        key: const ValueKey('jst-menu-import'),
      ),
    if (writable) ...[
      const PopupMenuDivider(),
      menuItem(
        context,
        StoreAction.clear,
        Icons.delete_sweep_outlined,
        unreadable ? 'Clear to start over…' : 'Clear…',
        destructive: true,
        enabled: count > 0 || unreadable,
        key: const ValueKey('jst-menu-clear'),
      ),
      if (controller.canWipe(store))
        menuItem(
          context,
          StoreAction.wipe,
          Icons.key_off_outlined,
          'Wipe, destroying the key…',
          destructive: true,
          key: const ValueKey('jst-menu-wipe'),
        ),
    ],
  ];
}

/// Runs [action] on [store]; [onAdded] gets the key of an added entry.
@internal
Future<void> runStoreAction(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  StoreAction action, {
  ValueChanged<String>? onAdded,
}) async {
  switch (action) {
    case StoreAction.refresh:
      await controller.refresh(store);
    case StoreAction.add:
      final key = await showNewEntryDialog(context, controller, store);
      if (key != null) onAdded?.call(key);
    case StoreAction.export:
      await showExportDialog(context, controller, store);
    case StoreAction.import:
      await showImportDialog(context, controller, store);
    case StoreAction.clear:
      await clearStore(context, controller, store);
    case StoreAction.wipe:
      await wipeStore(context, controller, store);
  }
}

/// A "more" button with [store]'s menu.
@internal
class StoreMenuButton extends StatelessWidget {
  /// The menu of [store].
  const StoreMenuButton({
    super.key,
    required this.controller,
    required this.store,
    this.withAdd = false,
    this.onAdded,
    this.icon = Icons.more_vert,
  });

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage acted on.
  final StorageAdminStore store;

  /// Whether the menu offers to add an entry.
  final bool withAdd;

  /// Gets the key of an added entry.
  final ValueChanged<String>? onAdded;

  /// The button's icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StoreAction>(
      key: ValueKey('jst-store-menu-${store.name}'),
      tooltip: 'Actions on ${store.name}',
      icon: Icon(icon),
      itemBuilder: (context) =>
          storeMenuItems(context, controller, store, withAdd: withAdd),
      onSelected: (action) =>
          runStoreAction(context, controller, store, action, onAdded: onAdded),
    );
  }
}
