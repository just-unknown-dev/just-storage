/// The sidebar of the wide layout: the storages, with what each holds.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../admin_style.dart';
import '../admin_utils.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';
import 'store_menu.dart';

/// A one-line summary of [store]: how many entries and how much, or what
/// went wrong.
@internal
String storeSummary(
  StorageAdminController controller,
  StorageAdminStore store,
) {
  if (!controller.isLoaded(store)) return 'Reading…';
  final error = controller.errorOf(store);
  if (error is StorageCorruptException) return 'Can\'t be read';
  if (error != null) return 'Could not be read';
  final all = controller.entriesOf(store);
  var bytes = 0;
  for (final e in all.entries) {
    bytes += utf8Length(e.key) + utf8Length(e.value);
  }
  return '${entries(all.length)} · ${formatBytes(bytes)}';
}

/// The storages, the selected one marked.
@internal
class StoreSidebar extends StatelessWidget {
  /// The sidebar over [controller]'s storages.
  const StoreSidebar({super.key, required this.controller});

  /// The screen's state.
  final StorageAdminController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;
    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('STORAGES', style: AdminStyle.overline(context)),
          ),
          SizedBox(
            height: 2,
            child: c.isBusy
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('jst-sidebar'),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              children: [
                for (final store in c.stores)
                  _StoreTile(controller: c, store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.controller, required this.store});

  final StorageAdminController controller;
  final StorageAdminStore store;

  Future<void> _menu(BuildContext context, Offset position) async {
    final action = await showMenuAt<StoreAction>(
      context,
      position,
      storeMenuItems(context, controller, store, withAdd: true),
    );
    if (action == null || !context.mounted) return;
    controller.select(store);
    await runStoreAction(
      context,
      controller,
      store,
      action,
      onAdded: (key) => controller.select(store, key: key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;
    final selected = c.selectedStore == store;
    final error = c.errorOf(store);
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('jst-store-${store.name}'),
          onTap: () => c.select(store),
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  store.isSecure
                      ? Icons.lock_outline
                      : Icons.inventory_2_outlined,
                  size: 20,
                  color: selected ? fg : cs.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      Text(
                        storeSummary(c, store),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AdminStyle.caption(
                          context,
                        ).copyWith(color: error != null ? cs.error : null),
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: cs.error,
                    ),
                  ),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Actions on ${store.name}',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.more_vert, size: 18, color: fg),
                    onPressed: () {
                      final box = context.findRenderObject()! as RenderBox;
                      _menu(
                        context,
                        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                      );
                    },
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
