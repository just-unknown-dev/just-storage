/// The workspace of the wide layout: the selected storage's header, its
/// entries beside the selected value, and its details.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../admin_style.dart';
import '../dialogs/entry_dialogs.dart';
import '../panes/details_pane.dart';
import '../panes/entries_pane.dart';
import '../panes/value_pane.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';
import 'store_menu.dart';
import 'store_sidebar.dart';

/// The selected storage: a header, then its entries and details in tabs.
@internal
class StoreWorkspace extends StatefulWidget {
  /// The workspace over [controller]'s selection.
  const StoreWorkspace({super.key, required this.controller});

  /// The screen's state.
  final StorageAdminController controller;

  @override
  State<StoreWorkspace> createState() => _StoreWorkspaceState();
}

class _StoreWorkspaceState extends State<StoreWorkspace>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final store = c.selectedStore;
    if (store == null) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No storages',
        message: 'Pass the storages to show in the screen\'s stores.',
      );
    }
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final error = c.errorOf(store);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  store.isSecure
                      ? Icons.lock_outline
                      : Icons.inventory_2_outlined,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          store.name,
                          key: const ValueKey('jst-workspace-title'),
                          style: text.titleLarge,
                        ),
                        if (store.isSecure)
                          AdminTag.secure(context)
                        else
                          AdminTag.plain(context),
                        AdminTag.neutral(context, storeSummary(c, store)),
                      ],
                    ),
                    if (store.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          store.description!,
                          style: AdminStyle.caption(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (!c.readOnly)
                FilledButton.tonalIcon(
                  key: const ValueKey('jst-add-entry'),
                  onPressed: error != null
                      ? null
                      : () async {
                          final key = await showNewEntryDialog(
                            context,
                            c,
                            store,
                          );
                          if (key != null) {
                            _tabs.index = 0;
                            c.select(store, key: key);
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add entry'),
                ),
              StoreMenuButton(
                controller: c,
                store: store,
                onAdded: (key) => c.select(store, key: key),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(key: ValueKey('jst-tab-entries'), text: 'Entries'),
            Tab(key: ValueKey('jst-tab-details'), text: 'Details'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _EntriesAndValue(controller: c, store: store),
              DetailsPane(controller: c, store: store),
            ],
          ),
        ),
      ],
    );
  }
}

/// The entries, and the selected value beside them when there is room, or
/// in a dialog when there isn't.
class _EntriesAndValue extends StatelessWidget {
  const _EntriesAndValue({required this.controller, required this.store});

  final StorageAdminController controller;
  final StorageAdminStore store;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth >= AdminStyle.sidePanelBreakpoint;
        final key = c.selectedKey;
        final entriesPane = EntriesPane(
          key: ValueKey('jst-entries-pane-${store.name}'),
          controller: c,
          store: store,
          onOpen: (key) {
            c.select(store, key: key);
            if (!side) showValueDialog(context, c, store, key);
          },
        );
        if (!side) return entriesPane;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: entriesPane),
            const VerticalDivider(width: 1),
            SizedBox(
              width: AdminStyle.sidePanelWidth,
              child: key == null
                  ? const EmptyState(
                      icon: Icons.touch_app_outlined,
                      title: 'No entry selected',
                      message:
                          'Select an entry to see its value. Right-click one '
                          'for more.',
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: ValuePane(
                        key: const ValueKey('jst-value-panel'),
                        controller: c,
                        store: store,
                        entryKey: key,
                        onKeyChanged: c.selectKey,
                        onClose: () => c.selectKey(null),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
