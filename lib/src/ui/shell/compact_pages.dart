/// The phone layout: a list of storages, a page per storage (entries and
/// details) and a page per entry.
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

/// Removes a phone page once the window is wide: the wide layout shows the
/// same selection.
mixin _PopWhenWide<T extends StatefulWidget> on State<T> {
  bool _popping = false;

  void popIfWide(BuildContext context) {
    if (_popping ||
        MediaQuery.sizeOf(context).width < AdminStyle.wideBreakpoint) {
      return;
    }
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Remove this page's own route: two pages popping "the top route" in
      // one frame would both pop the same one.
      final route = mounted ? ModalRoute.of(context) : null;
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

/// Selects [store] and pushes its page.
@internal
Future<void> openCompactStore(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
) {
  controller.select(store);
  return pushAdminPage<void>(
    context,
    CompactStorePage(controller: controller, store: store),
  );
}

/// Selects [key] of [store] and pushes its page.
@internal
Future<void> openCompactEntry(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) {
  controller.select(store, key: key);
  return pushAdminPage<void>(
    context,
    CompactEntryPage(controller: controller, store: store, entryKey: key),
  );
}

/// The storages, as cards.
@internal
class CompactStoreList extends StatelessWidget {
  /// The list of [controller]'s storages.
  const CompactStoreList({super.key, required this.controller});

  /// The screen's state.
  final StorageAdminController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.stores.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No storages',
        message: 'Pass the storages to show in the screen\'s stores.',
      );
    }
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const ValueKey('jst-store-list'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final store in c.stores) _StoreCard(controller: c, store: store),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.controller, required this.store});

  final StorageAdminController controller;
  final StorageAdminStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final error = controller.errorOf(store);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        key: ValueKey('jst-store-${store.name}'),
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        onTap: () => openCompactStore(context, controller, store),
        leading: CircleAvatar(
          backgroundColor: store.isSecure
              ? cs.tertiaryContainer
              : cs.secondaryContainer,
          child: Icon(
            store.isSecure ? Icons.lock_outline : Icons.inventory_2_outlined,
            color: store.isSecure
                ? cs.onTertiaryContainer
                : cs.onSecondaryContainer,
          ),
        ),
        title: Text(
          store.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [storeSummary(controller, store), ?store.description].join('\n'),
          style: error == null ? null : TextStyle(color: cs.error),
        ),
        isThreeLine: store.description != null,
        trailing: StoreMenuButton(controller: controller, store: store),
      ),
    );
  }
}

/// One storage on a phone: its entries and details in tabs.
@internal
class CompactStorePage extends StatefulWidget {
  /// The page of [store].
  const CompactStorePage({
    super.key,
    required this.controller,
    required this.store,
  });

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage shown.
  final StorageAdminStore store;

  @override
  State<CompactStorePage> createState() => _CompactStorePageState();
}

class _CompactStorePageState extends State<CompactStorePage>
    with SingleTickerProviderStateMixin, _PopWhenWide {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_changed);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.viewOf(widget.store).addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.viewOf(widget.store).removeListener(_changed);
    _tabs.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _open(String key) =>
      openCompactEntry(context, widget.controller, widget.store, key);

  @override
  Widget build(BuildContext context) {
    popIfWide(context);
    final c = widget.controller;
    final store = widget.store;
    final view = c.viewOf(store);
    final canAdd = !c.readOnly && c.errorOf(store) == null;
    return PopScope(
      // Back leaves selection mode before it leaves the page.
      canPop: !view.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) view.clearChecked();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(store.name, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              if (store.isSecure)
                AdminTag.secure(context)
              else
                AdminTag.plain(context),
            ],
          ),
          actions: [
            if (c.isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            StoreMenuButton(controller: c, store: store, onAdded: _open),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(key: ValueKey('jst-tab-entries'), text: 'Entries'),
              Tab(key: ValueKey('jst-tab-details'), text: 'Details'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            controller: _tabs,
            children: [
              EntriesPane(
                controller: c,
                store: store,
                compact: true,
                onOpen: _open,
              ),
              DetailsPane(controller: c, store: store),
            ],
          ),
        ),
        floatingActionButton: canAdd && _tabs.index == 0 && !view.selecting
            ? FloatingActionButton.extended(
                key: const ValueKey('jst-add-entry'),
                onPressed: () async {
                  final key = await showNewEntryDialog(context, c, store);
                  if (key != null && context.mounted) _open(key);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add entry'),
              )
            : null,
      ),
    );
  }
}

/// One entry on a phone.
@internal
class CompactEntryPage extends StatefulWidget {
  /// The page of [entryKey] in [store].
  const CompactEntryPage({
    super.key,
    required this.controller,
    required this.store,
    required this.entryKey,
  });

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage holding the entry.
  final StorageAdminStore store;

  /// The entry's key.
  final String entryKey;

  @override
  State<CompactEntryPage> createState() => _CompactEntryPageState();
}

class _CompactEntryPageState extends State<CompactEntryPage> with _PopWhenWide {
  late String _key = widget.entryKey;

  @override
  Widget build(BuildContext context) {
    popIfWide(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _key,
          key: const ValueKey('jst-entry-title'),
          overflow: TextOverflow.ellipsis,
          style: AdminStyle.mono(
            context,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ValuePane(
            controller: widget.controller,
            store: widget.store,
            entryKey: _key,
            showKey: false,
            onKeyChanged: (key) {
              if (key == null) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _key = key);
                widget.controller.selectKey(key);
              }
            },
          ),
        ),
      ),
    );
  }
}
