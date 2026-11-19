import 'dart:convert';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';
import '../storage_admin_controller.dart';

/// The entries of one storage — the secure one when [secure] — with a
/// search field, a type badge on each value, and adding, editing, copying
/// and deleting.
///
/// Secure values are hidden until shown, and only their keys are searched
/// while they are.
@internal
class EntriesTab extends StatefulWidget {
  /// The tab over [controller]'s secure storage when [secure], else its
  /// standard one.
  const EntriesTab({super.key, required this.controller, required this.secure});

  /// What the tab shows.
  final StorageAdminController controller;

  /// Whether it shows the secure storage.
  final bool secure;

  @override
  State<EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends State<EntriesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late bool _showValues = !widget.secure;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(EntriesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onSearchChanged() =>
      setState(() => _searchQuery = _searchController.text.toLowerCase());

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Map<String, String> get _allEntries =>
      widget.controller.entries(secure: widget.secure);

  List<MapEntry<String, String>> get _filteredEntries {
    final entries = _allEntries.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (_searchQuery.isEmpty) return entries;
    return entries
        .where(
          (e) =>
              e.key.toLowerCase().contains(_searchQuery) ||
              (_showValues && e.value.toLowerCase().contains(_searchQuery)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = _filteredEntries;
    final error = controller.error(secure: widget.secure);
    final unreadable = error is StorageCorruptException;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          if (error != null) _ErrorBanner(error: error),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _showValues
                    ? 'Search keys or values…'
                    : 'Search keys…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text(
                  '${entries.length}'
                  '${_searchQuery.isNotEmpty ? ' matching' : ''} '
                  'entr${entries.length == 1 ? 'y' : 'ies'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (widget.secure)
                  IconButton(
                    icon: Icon(
                      _showValues
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    tooltip: _showValues ? 'Hide values' : 'Show values',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _showValues = !_showValues),
                  ),
                if (_allEntries.isNotEmpty || unreadable)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Clear all'),
                    onPressed: () => _confirmClearAll(context),
                  ),
              ],
            ),
          ),

          Expanded(
            child: entries.isEmpty
                ? _EmptyState(
                    isFiltered: _searchQuery.isNotEmpty,
                    secure: widget.secure,
                    onAdd: unreadable ? null : () => _showEntryDialog(context),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _EntryCard(
                      entry: entries[i],
                      secure: widget.secure,
                      showValue: _showValues,
                      onEdit: () =>
                          _showEntryDialog(context, existing: entries[i]),
                      onDelete: () => _confirmDelete(context, entries[i].key),
                      onCopy: () => _copyToClipboard(context, entries[i].value),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: unreadable
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showEntryDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs & actions
  // ---------------------------------------------------------------------------

  Future<void> _showEntryDialog(
    BuildContext context, {
    MapEntry<String, String>? existing,
  }) async {
    final result = await showDialog<MapEntry<String, String>>(
      context: context,
      builder: (_) => _EntryDialog(
        existingKey: existing?.key,
        existingValue: existing?.value,
        secure: widget.secure,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await widget.controller.writeEntry(
        result.key,
        result.value,
        secure: widget.secure,
      );
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not save: $e');
    }
  }

  Future<void> _confirmDelete(BuildContext context, String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Delete '),
              TextSpan(
                text: '"$key"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: '?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.controller.deleteEntry(key, secure: widget.secure);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not delete: $e');
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await confirmClear(
      context,
      count: _allEntries.length,
      secure: widget.secure,
      unreadable:
          widget.controller.error(secure: widget.secure)
              is StorageCorruptException,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await widget.controller.clearAll(secure: widget.secure);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not clear: $e');
    }
  }

  void _copyToClipboard(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Value copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: colorScheme.onError)),
        backgroundColor: colorScheme.error,
      ),
    );
  }
}

/// Asks whether to remove every entry of a storage — the secure one when
/// [secure] — holding [count] entries, or [unreadable]. True when the user
/// agrees.
@internal
Future<bool> confirmClear(
  BuildContext context, {
  required int count,
  required bool secure,
  required bool unreadable,
}) async {
  final label = secure ? 'secure' : 'standard';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Clear ${secure ? 'secure' : 'standard'} storage'),
      content: Text(
        unreadable
            ? 'The $label storage can\'t be read. Clearing it removes what is '
                  'there for good and starts over with an empty one.'
            : 'This permanently removes all $count '
                  'entr${count == 1 ? 'y' : 'ies'} from $label storage.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Clear all'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

// =============================================================================
// Entry card
// =============================================================================

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.secure,
    required this.showValue,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
  });

  final MapEntry<String, String> entry;
  final bool secure;
  final bool showValue;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final type = showValue ? _detectValueType(entry.value) : null;
    final preview = !showValue
        ? '••••••••'
        : entry.value.length > 120
        ? '${entry.value.substring(0, 120)}…'
        : entry.value;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: secure
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer,
          child: Icon(
            type == null ? Icons.lock_outline : _typeIcon(type),
            size: 17,
            color: secure
                ? colorScheme.onTertiaryContainer
                : colorScheme.onSecondaryContainer,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.key,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (type != null) ...[
              const SizedBox(width: 6),
              _TypeBadge(type: type),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            preview,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: onCopy,
              tooltip: 'Copy value',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: colorScheme.error,
              ),
              onPressed: onDelete,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Value type detection & badges
// =============================================================================

enum _ValueType { json, number, boolean, string }

_ValueType _detectValueType(String value) {
  if (value == 'true' || value == 'false') return _ValueType.boolean;
  if (double.tryParse(value) != null) return _ValueType.number;
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map || decoded is List) return _ValueType.json;
  } on FormatException {
    // Not JSON: a plain string.
  }
  return _ValueType.string;
}

IconData _typeIcon(_ValueType type) => switch (type) {
  _ValueType.json => Icons.data_object,
  _ValueType.number => Icons.tag,
  _ValueType.boolean => Icons.toggle_on_outlined,
  _ValueType.string => Icons.text_fields,
};

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final _ValueType type;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      _ValueType.json => ('JSON', const Color(0xFF00897B)),
      _ValueType.number => ('NUM', const Color(0xFF1E88E5)),
      _ValueType.boolean => ('BOOL', const Color(0xFF8E24AA)),
      _ValueType.string => ('STR', const Color(0xFF757575)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// =============================================================================
// Add / Edit dialog
// =============================================================================

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    this.existingKey,
    this.existingValue,
    required this.secure,
  });

  final String? existingKey;
  final String? existingValue;
  final bool secure;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final TextEditingController _keyCtrl = TextEditingController(
    text: widget.existingKey ?? '',
  );
  late final TextEditingController _valueCtrl = TextEditingController(
    text: widget.existingValue ?? '',
  );
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.existingKey != null;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      _valueCtrl.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(_valueCtrl.text));
    } on FormatException {
      // Not JSON: leave it as it is.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_isEditing ? 'Edit entry' : 'New entry'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _keyCtrl,
                readOnly: _isEditing,
                autofocus: !_isEditing,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Key',
                  border: const OutlineInputBorder(),
                  filled: _isEditing,
                  fillColor: _isEditing
                      ? colorScheme.surfaceContainerHighest
                      : null,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Key is required' : null,
              ),
              const SizedBox(height: 12),
              // An empty value is a value: the storage keeps it.
              TextFormField(
                controller: _valueCtrl,
                autofocus: _isEditing,
                maxLines: 7,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: 'Value',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: IconButton(
                      icon: const Icon(
                        Icons.format_align_left_outlined,
                        size: 18,
                      ),
                      tooltip: 'Format as JSON',
                      onPressed: _formatJson,
                    ),
                  ),
                ),
              ),
              if (widget.secure) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock, size: 13, color: colorScheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Will be encrypted with AES-256-GCM',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                MapEntry(_keyCtrl.text.trim(), _valueCtrl.text),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isFiltered,
    required this.secure,
    required this.onAdd,
  });

  final bool isFiltered;
  final bool secure;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltered
                ? Icons.search_off
                : secure
                ? Icons.lock_outline
                : Icons.storage_outlined,
            size: 56,
            color: muted,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered ? 'No matching entries' : 'No entries yet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Try a different search term.'
                : 'Write your first ${secure ? 'secure ' : ''}key-value pair.',
            style: TextStyle(color: muted),
          ),
          if (!isFiltered && onAdd != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Error banner
// =============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = error is StorageCorruptException
        ? 'This storage can\'t be read, and is left as it is. '
              'Clear all to start over.\n$error'
        : 'Could not read this storage.\n$error';
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
      ),
    );
  }
}
