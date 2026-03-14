import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage_provider.dart';

/// Displays all key-value entries for either the standard or secure store,
/// with search-filtering, inline type badges, and full CRUD operations.
class EntriesTab extends StatefulWidget {
  final StorageProvider provider;

  /// When `true`, shows and manages [StorageProvider.secureEntries].
  /// When `false`, shows and manages [StorageProvider.standardEntries].
  final bool isSecure;

  const EntriesTab({
    super.key,
    required this.provider,
    required this.isSecure,
  });

  @override
  State<EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends State<EntriesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.provider.addListener(_onProviderChanged);
  }

  @override
  void didUpdateWidget(EntriesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      oldWidget.provider.removeListener(_onProviderChanged);
      widget.provider.addListener(_onProviderChanged);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onSearchChanged() =>
      setState(() => _searchQuery = _searchController.text.toLowerCase());

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Map<String, String> get _allEntries => widget.isSecure
      ? widget.provider.secureEntries
      : widget.provider.standardEntries;

  List<MapEntry<String, String>> get _filteredEntries {
    final entries = _allEntries.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (_searchQuery.isEmpty) return entries;
    return entries
        .where(
          (e) =>
              e.key.toLowerCase().contains(_searchQuery) ||
              e.value.toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.provider.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = _filteredEntries;

    return Scaffold(
      body: Column(
        children: [
          // Error banner
          if (widget.provider.error != null)
            _ErrorBanner(message: widget.provider.error!),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search keys or values…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
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

          // Count + clear-all row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text(
                  '${entries.length}'
                  '${_searchQuery.isNotEmpty ? ' matching' : ''} '
                  'entr${entries.length == 1 ? 'y' : 'ies'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                if (_allEntries.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
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

          // List or empty state
          Expanded(
            child: entries.isEmpty
                ? _EmptyState(
                    isFiltered: _searchQuery.isNotEmpty,
                    isSecure: widget.isSecure,
                    onAdd: () => _showEntryDialog(context),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _EntryCard(
                      entry: entries[i],
                      isSecure: widget.isSecure,
                      onEdit: () =>
                          _showEntryDialog(context, existing: entries[i]),
                      onDelete: () => _confirmDelete(context, entries[i].key),
                      onCopy: () => _copyToClipboard(context, entries[i].value),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
        isSecure: widget.isSecure,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await widget.provider.writeEntry(
        result.key,
        result.value,
        isSecure: widget.isSecure,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Failed to save: $e');
    }
  }

  Future<void> _confirmDelete(BuildContext context, String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
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
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.provider.deleteEntry(key, isSecure: widget.isSecure);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Failed to delete: $e');
    }
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final count = _allEntries.length;
    final label = widget.isSecure ? 'secure' : 'standard';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all entries'),
        content: Text(
          'This will permanently remove all $count '
          'entr${count == 1 ? 'y' : 'ies'} from $label storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await widget.provider.clearAll(isSecure: widget.isSecure);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

// =============================================================================
// Entry card
// =============================================================================

class _EntryCard extends StatelessWidget {
  final MapEntry<String, String> entry;
  final bool isSecure;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  const _EntryCard({
    required this.entry,
    required this.isSecure,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final type = _detectValueType(entry.value);
    final preview = entry.value.length > 120
        ? '${entry.value.substring(0, 120)}…'
        : entry.value;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isSecure
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer,
          child: Icon(
            _typeIcon(type),
            size: 17,
            color: isSecure
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
            const SizedBox(width: 6),
            _TypeBadge(type: type),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            preview,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
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

enum _ValueType { json, number, bool_, string }

_ValueType _detectValueType(String value) {
  if (value == 'true' || value == 'false') return _ValueType.bool_;
  if (double.tryParse(value) != null) return _ValueType.number;
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map || decoded is List) return _ValueType.json;
  } catch (_) {}
  return _ValueType.string;
}

IconData _typeIcon(_ValueType type) => switch (type) {
      _ValueType.json => Icons.data_object,
      _ValueType.number => Icons.tag,
      _ValueType.bool_ => Icons.toggle_on_outlined,
      _ValueType.string => Icons.text_fields,
    };

class _TypeBadge extends StatelessWidget {
  final _ValueType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      _ValueType.json => ('JSON', const Color(0xFF00897B)),
      _ValueType.number => ('NUM', const Color(0xFF1E88E5)),
      _ValueType.bool_ => ('BOOL', const Color(0xFF8E24AA)),
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
  final String? existingKey;
  final String? existingValue;
  final bool isSecure;

  const _EntryDialog({
    this.existingKey,
    this.existingValue,
    required this.isSecure,
  });

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valueCtrl;
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.existingKey != null;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.existingKey ?? '');
    _valueCtrl = TextEditingController(text: widget.existingValue ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      final pretty = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(_valueCtrl.text));
      _valueCtrl.text = pretty;
    } catch (_) {
      // Not valid JSON — leave as-is
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
              // Key field
              TextFormField(
                controller: _keyCtrl,
                readOnly: _isEditing,
                autofocus: !_isEditing,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Key',
                  border: const OutlineInputBorder(),
                  filled: _isEditing,
                  fillColor:
                      _isEditing ? colorScheme.surfaceContainerHighest : null,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Key is required' : null,
              ),
              const SizedBox(height: 12),

              // Value field
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
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Value is required' : null,
              ),

              // Secure-mode note
              if (widget.isSecure) ...[
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
  final bool isFiltered;
  final bool isSecure;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.isFiltered,
    required this.isSecure,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltered
                ? Icons.search_off
                : isSecure
                    ? Icons.lock_outline
                    : Icons.storage_outlined,
            size: 56,
            color: Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered ? 'No matching entries' : 'No entries yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Try a different search term.'
                : 'Write your first ${isSecure ? 'secure ' : ''}key-value pair.',
            style: const TextStyle(color: Colors.grey),
          ),
          if (!isFiltered) ...[
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
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
