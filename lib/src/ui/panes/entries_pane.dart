/// One storage's entries: search, order, hidden values, check boxes for
/// working on several at once, and a menu on each.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../admin_style.dart';
import '../admin_utils.dart';
import '../dialogs/entry_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';
import '../storage_admin_controller.dart';
import '../store_view.dart';
import '../widgets/admin_widgets.dart';

/// The entries of [store], filtered, ordered and checkable.
@internal
class EntriesPane extends StatefulWidget {
  /// The entries of [store]; [onOpen] shows one.
  const EntriesPane({
    super.key,
    required this.controller,
    required this.store,
    required this.onOpen,
    this.compact = false,
  });

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage shown.
  final StorageAdminStore store;

  /// Shows a key: in the value panel, a dialog or a page.
  final ValueChanged<String> onOpen;

  /// Whether this is the phone layout: two-line rows, check boxes only in
  /// selection mode.
  final bool compact;

  @override
  State<EntriesPane> createState() => _EntriesPaneState();
}

class _EntriesPaneState extends State<EntriesPane> {
  late final TextEditingController _search = TextEditingController(
    text: _view.query,
  );

  StorageAdminController get _c => widget.controller;
  StoreView get _view => _c.viewOf(widget.store);

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _view.addListener(_changed);
    _search.addListener(() => _view.query = _search.text);
  }

  @override
  void didUpdateWidget(EntriesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.store != widget.store) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.viewOf(oldWidget.store).removeListener(_changed);
      _c.addListener(_changed);
      _view.addListener(_changed);
      _search.text = _view.query;
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _view.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The entries to list: matching the search, in the chosen order.
  List<MapEntry<String, String>> _rows() {
    final view = _view;
    final query = view.query.trim().toLowerCase();
    final rows = [
      for (final e in _c.entriesOf(widget.store).entries)
        if (query.isEmpty ||
            e.key.toLowerCase().contains(query) ||
            (view.showValues && e.value.toLowerCase().contains(query)))
          e,
    ];
    int byKey(MapEntry<String, String> a, MapEntry<String, String> b) =>
        a.key.compareTo(b.key);
    switch (view.sort) {
      case EntrySort.keyAscending:
        rows.sort(byKey);
      case EntrySort.keyDescending:
        rows.sort((a, b) => byKey(b, a));
      case EntrySort.largest:
        rows.sort((a, b) {
          final bySize = b.value.length.compareTo(a.value.length);
          return bySize != 0 ? bySize : byKey(a, b);
        });
      case EntrySort.recent:
        final store = widget.store;
        rows.sort((a, b) {
          final ta = _c.changedAt(store, a.key);
          final tb = _c.changedAt(store, b.key);
          if (ta != null && tb != null) return tb.compareTo(ta);
          if (ta != null) return -1;
          if (tb != null) return 1;
          return byKey(a, b);
        });
    }
    return rows;
  }

  Future<void> _add() async {
    final key = await showNewEntryDialog(context, _c, widget.store);
    if (key != null && mounted) widget.onOpen(key);
  }

  Future<void> _rowMenu(String key, Offset position) async {
    final c = _c;
    final choice = await showMenuAt<String>(context, position, [
      menuItem(context, 'open', Icons.open_in_new, 'Open'),
      menuItem(context, 'copy-key', Icons.key_outlined, 'Copy key'),
      menuItem(context, 'copy-value', Icons.copy, 'Copy value'),
      if (!c.readOnly) ...[
        const PopupMenuDivider(),
        menuItem(context, 'rename', Icons.drive_file_rename_outline, 'Rename…'),
        menuItem(context, 'duplicate', Icons.copy_all, 'Duplicate…'),
        menuItem(
          context,
          'delete',
          Icons.delete_outline,
          'Delete…',
          destructive: true,
        ),
      ],
    ]);
    if (choice == null || !mounted) return;
    final store = widget.store;
    switch (choice) {
      case 'open':
        widget.onOpen(key);
      case 'copy-key':
        await copyText(context, key, what: 'Key');
      case 'copy-value':
        final value = c.entriesOf(store)[key];
        if (value != null) await copyText(context, value, what: 'Value');
      case 'rename':
        final to = await renameEntry(context, c, store, key);
        if (to != null && c.selectedKey == key) c.selectKey(to);
      case 'duplicate':
        await duplicateEntry(context, c, store, key);
      case 'delete':
        await deleteEntries(context, c, store, [key]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final store = widget.store;
    if (!c.isLoaded(store)) {
      return const Center(child: CircularProgressIndicator());
    }
    final view = _view;
    final all = c.entriesOf(store);
    final error = c.errorOf(store);
    final rows = _rows();
    final selecting = !widget.compact || view.selecting;

    final Widget list;
    if (error != null && all.isEmpty) {
      list = const SizedBox.shrink();
    } else if (all.isEmpty) {
      list = EmptyState(
        icon: store.isSecure ? Icons.lock_outline : Icons.inventory_2_outlined,
        title: 'No entries yet',
        message: c.readOnly
            ? 'What the app stores in ${store.name} shows up here as it '
                  'writes it.'
            : 'Add one here, or import an export. What the app writes shows '
                  'up as it happens.',
        action: c.readOnly
            ? null
            : FilledButton.icon(
                key: const ValueKey('jst-empty-add'),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add entry'),
              ),
      );
    } else if (rows.isEmpty) {
      list = EmptyState(
        icon: Icons.search_off,
        title: 'No matches',
        message: view.showValues
            ? 'No key or value contains "${view.query.trim()}".'
            : 'No key contains "${view.query.trim()}". Hidden values are '
                  'not searched.',
        action: TextButton(
          onPressed: _search.clear,
          child: const Text('Clear the search'),
        ),
      );
    } else {
      list = ListView.builder(
        key: ValueKey('jst-entries-${store.name}'),
        padding: EdgeInsets.only(bottom: widget.compact ? 96 : 24),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final e = rows[i];
          final row = _EntryRow(
            entry: e,
            kind: c.kindOf(store, e.key, e.value),
            hidden: !view.showValues,
            recent: c.changedAt(store, e.key) != null,
            selected: !widget.compact && c.selectedKey == e.key,
            checkbox: selecting,
            checked: view.isChecked(e.key),
            compact: widget.compact,
            onTap: widget.compact && view.selecting
                ? () => view.toggle(e.key)
                : () => widget.onOpen(e.key),
            onCheck: () => view.toggle(e.key),
            onMenu: (position) => _rowMenu(e.key, position),
            onLongPress: widget.compact
                ? () {
                    view.selecting = true;
                    view.toggle(e.key);
                  }
                : null,
          );
          return row;
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _ErrorBanner(controller: c, store: store, error: error),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Row(
            children: [
              Expanded(child: _searchField(context)),
              const SizedBox(width: 4),
              _sortButton(context),
              if (store.isSecure)
                IconButton(
                  key: const ValueKey('jst-toggle-values'),
                  tooltip: view.showValues ? 'Hide values' : 'Show values',
                  icon: Icon(
                    view.showValues
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => view.showValues = !view.showValues,
                ),
              if (widget.compact && !view.selecting && all.isNotEmpty)
                IconButton(
                  key: const ValueKey('jst-select-mode'),
                  tooltip: 'Select',
                  icon: const Icon(Icons.checklist),
                  onPressed: () => view.selecting = true,
                ),
            ],
          ),
        ),
        if (view.checked.isNotEmpty || (widget.compact && view.selecting))
          _SelectionBar(
            controller: c,
            store: store,
            visible: [for (final e in rows) e.key],
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              view.query.trim().isEmpty
                  ? entries(all.length)
                  : '${rows.length} of ${entries(all.length)}',
              key: const ValueKey('jst-entry-count'),
              style: AdminStyle.caption(context),
            ),
          ),
        const Divider(height: 1),
        Expanded(child: list),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final view = _view;
    return TextField(
      key: const ValueKey('jst-search'),
      controller: _search,
      decoration: InputDecoration(
        hintText: view.showValues ? 'Search keys and values' : 'Search keys',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: view.query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear the search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _search.clear,
              ),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _sortButton(BuildContext context) {
    final view = _view;
    return PopupMenuButton<EntrySort>(
      key: const ValueKey('jst-sort'),
      tooltip: 'Order: ${view.sort.label}',
      icon: const Icon(Icons.sort),
      initialValue: view.sort,
      onSelected: (sort) => view.sort = sort,
      itemBuilder: (context) => [
        for (final sort in EntrySort.values)
          CheckedPopupMenuItem(
            value: sort,
            checked: sort == view.sort,
            child: Text(sort.label),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.controller,
    required this.store,
    required this.error,
  });

  final StorageAdminController controller;
  final StorageAdminStore store;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final unreadable = error is StorageCorruptException;
    return MessageBanner(
      key: const ValueKey('jst-store-error'),
      tone: BannerTone.error,
      message: unreadable
          ? '${store.name} can\'t be read, and is left as it is: '
                '${describeError(error)}'
          : 'Could not read ${store.name}: ${describeError(error)}',
      actions: [
        TextButton(
          onPressed: () => controller.refresh(store),
          child: const Text('Try again'),
        ),
        if (unreadable && !controller.readOnly)
          TextButton(
            key: const ValueKey('jst-error-clear'),
            onPressed: () => clearStore(context, controller, store),
            child: const Text('Clear to start over…'),
          ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.controller,
    required this.store,
    required this.visible,
  });

  final StorageAdminController controller;
  final StorageAdminStore store;

  /// The keys listed now, which "Select all" checks.
  final List<String> visible;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final view = controller.viewOf(store);
    final checked = view.checked;
    final allChecked = visible.isNotEmpty && visible.every(view.isChecked);
    return Container(
      key: const ValueKey('jst-selection-bar'),
      color: cs.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Done',
            icon: Icon(Icons.close, color: cs.onSecondaryContainer),
            onPressed: view.clearChecked,
          ),
          Expanded(
            child: Text(
              '${checked.length} selected',
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('jst-select-all'),
            tooltip: allChecked ? 'Select none' : 'Select all',
            icon: Icon(
              allChecked ? Icons.deselect : Icons.select_all,
              color: cs.onSecondaryContainer,
            ),
            onPressed: () => view.checkAll(allChecked ? const [] : visible),
          ),
          IconButton(
            key: const ValueKey('jst-export-selected'),
            tooltip: 'Export selected…',
            icon: Icon(Icons.upload_outlined, color: cs.onSecondaryContainer),
            onPressed: checked.isEmpty
                ? null
                : () => showExportDialog(
                    context,
                    controller,
                    store,
                    keys: checked,
                  ),
          ),
          if (!controller.readOnly)
            IconButton(
              key: const ValueKey('jst-delete-selected'),
              tooltip: 'Delete selected…',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: checked.isEmpty
                  ? null
                  : () async {
                      if (await deleteEntries(
                        context,
                        controller,
                        store,
                        checked,
                      )) {
                        view.clearChecked();
                      }
                    },
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.kind,
    required this.hidden,
    required this.recent,
    required this.selected,
    required this.checkbox,
    required this.checked,
    required this.compact,
    required this.onTap,
    required this.onCheck,
    required this.onMenu,
    required this.onLongPress,
  });

  final MapEntry<String, String> entry;
  final ValueKind kind;
  final bool hidden;
  final bool recent;
  final bool selected;
  final bool checkbox;
  final bool checked;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onCheck;
  final void Function(Offset position) onMenu;
  final VoidCallback? onLongPress;

  /// A one-line preview of the value.
  String get _preview {
    if (hidden) return '••••••••';
    final v = entry.value;
    if (v.isEmpty) return '(empty)';
    final cut = v.length > 200 ? v.substring(0, 200) : v;
    return cut.replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyStyle = AdminStyle.mono(
      context,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final previewStyle = AdminStyle.mono(
      context,
      fontSize: 12,
      height: 1.3,
      color: cs.onSurfaceVariant,
    );
    final box = checkbox
        ? Checkbox(
            value: checked,
            visualDensity: VisualDensity.compact,
            onChanged: (_) => onCheck(),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              hidden ? Icons.lock_outline : kind.icon,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          );
    final background = selected
        ? cs.secondaryContainer
        : checked
        ? cs.secondaryContainer.withValues(alpha: 0.45)
        : null;

    final Widget content;
    if (compact) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            box,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: keyStyle,
                        ),
                      ),
                      if (recent) ...[
                        const SizedBox(width: 6),
                        const RecentDot(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: previewStyle,
                  ),
                ],
              ),
            ),
            if (!hidden) ...[const SizedBox(width: 8), KindBadge(kind: kind)],
          ],
        ),
      );
    } else {
      content = SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 4),
            box,
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: keyStyle,
                    ),
                  ),
                  if (recent) ...[const SizedBox(width: 6), const RecentDot()],
                ],
              ),
            ),
            SizedBox(
              width: 64,
              child: hidden
                  ? null
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: KindBadge(kind: kind),
                    ),
            ),
            Expanded(
              flex: 6,
              child: Text(
                _preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: previewStyle,
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                formatBytes(utf8Length(entry.value)),
                textAlign: TextAlign.right,
                style: AdminStyle.caption(context),
              ),
            ),
            Builder(
              builder: (context) => IconButton(
                tooltip: 'More',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: () {
                  final box = context.findRenderObject()! as RenderBox;
                  onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                },
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      key: ValueKey('jst-entry-${entry.key}'),
      color: background ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: content,
      ),
    );
  }
}

/// Opens the dialog for a new entry in [store] and then [onAdded] with it.
@internal
Future<void> addEntry(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store, {
  ValueChanged<String>? onAdded,
}) async {
  final key = await showNewEntryDialog(context, controller, store);
  if (key != null) onAdded?.call(key);
}
