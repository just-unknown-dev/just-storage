/// One entry in full: its value as text, formatted JSON or a tree, edited
/// in place, renamed, duplicated or deleted. The side panel on wide
/// screens, a dialog when there is no room for one, a page on phones.
@internal
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_style.dart';
import '../admin_utils.dart';
import '../dialogs/entry_dialogs.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/json_tree.dart';

/// Shows [key] of [store] in a dialog; it follows a rename and closes on a
/// delete.
@internal
Future<void> showValueDialog(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) => showDialog<void>(
  context: context,
  builder: (_) => _ValueDialog(controller: controller, store: store, key0: key),
);

class _ValueDialog extends StatefulWidget {
  const _ValueDialog({
    required this.controller,
    required this.store,
    required this.key0,
  });

  final StorageAdminController controller;
  final StorageAdminStore store;
  final String key0;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late String _key = widget.key0;

  @override
  Widget build(BuildContext context) {
    return AdminDialog(
      title: widget.store.name,
      width: 720,
      fill: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: ValuePane(
        controller: widget.controller,
        store: widget.store,
        entryKey: _key,
        onKeyChanged: (key) {
          if (key == null) {
            Navigator.pop(context);
          } else {
            setState(() => _key = key);
          }
        },
      ),
    );
  }
}

enum _Mode { text, formatted, tree }

/// [entryKey] of [store]: its value and what can be done with it.
@internal
class ValuePane extends StatefulWidget {
  /// A pane for [entryKey] of [store].
  const ValuePane({
    super.key,
    required this.controller,
    required this.store,
    required this.entryKey,
    this.showKey = true,
    this.onKeyChanged,
    this.onClose,
  });

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage holding the entry.
  final StorageAdminStore store;

  /// The entry's key.
  final String entryKey;

  /// Whether the key heads the pane (a page shows it in its app bar).
  final bool showKey;

  /// Called with the new key after a rename, and with null after a delete.
  final ValueChanged<String?>? onKeyChanged;

  /// Shows a close button that calls this.
  final VoidCallback? onClose;

  @override
  State<ValuePane> createState() => _ValuePaneState();
}

class _ValuePaneState extends State<ValuePane> {
  _Mode? _mode;
  bool _editing = false;
  final _edit = TextEditingController();
  final _editFocus = FocusNode();

  /// The value when editing started: told apart from a change made since.
  String? _base;
  bool _saving = false;
  String? _saveError;
  String? _lastSeen;
  bool _showAll = false;

  static const int _shownChars = 100000;

  StorageAdminController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.viewOf(widget.store).addListener(_changed);
    _edit.addListener(_changed);
  }

  @override
  void didUpdateWidget(ValuePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.store != widget.store) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.viewOf(oldWidget.store).removeListener(_changed);
      _c.addListener(_changed);
      _c.viewOf(widget.store).addListener(_changed);
    }
    if (oldWidget.entryKey != widget.entryKey ||
        oldWidget.store != widget.store) {
      _editing = false;
      _saveError = null;
      _lastSeen = null;
      _showAll = false;
      _mode = null;
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.viewOf(widget.store).removeListener(_changed);
    _edit.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String? get _value => _c.entriesOf(widget.store)[widget.entryKey];

  void _startEdit(String value) {
    setState(() {
      _editing = true;
      _base = value;
      _edit.text = value;
      _saveError = null;
    });
    _editFocus.requestFocus();
  }

  void _cancelEdit() => setState(() {
    _editing = false;
    _saveError = null;
  });

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _c.write(widget.store, widget.entryKey, _edit.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Not saved: ${describeError(e)}';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
    showAdminMessage(context, 'Saved "${widget.entryKey}".');
  }

  void _formatEdit({required bool pretty}) {
    final check = checkJson(_edit.text);
    if (!check.isValid) return;
    _edit.text = pretty ? prettyJson(check.value) : _minify(check.value);
  }

  static String _minify(Object? value) => jsonEncode(value);

  Future<void> _menu(String action) async {
    final c = _c;
    final store = widget.store;
    final key = widget.entryKey;
    switch (action) {
      case 'rename':
        final to = await renameEntry(context, c, store, key);
        if (to != null) widget.onKeyChanged?.call(to);
      case 'duplicate':
        await duplicateEntry(context, c, store, key);
      case 'copy-key':
        await copyText(context, key, what: 'Key');
      case 'delete':
        if (await deleteEntries(context, c, store, [key])) {
          widget.onKeyChanged?.call(null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final store = widget.store;
    final key = widget.entryKey;
    final view = c.viewOf(store);
    final value = _value;
    if (value != null) _lastSeen = value;
    final hidden = store.isSecure && !view.showValues;
    final kind = value == null ? null : c.kindOf(store, key, value);
    final recent = c.changedAt(store, key) != null;

    final header = <Widget>[
      if (widget.showKey || widget.onClose != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: widget.showKey
                  ? SelectableText(
                      key,
                      key: const ValueKey('jst-value-key'),
                      style: AdminStyle.mono(
                        context,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (widget.onClose != null)
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                onPressed: widget.onClose,
              ),
          ],
        ),
      if (value != null) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!hidden && kind != null) KindBadge(kind: kind),
            AdminTag.neutral(
              context,
              hidden
                  ? formatBytes(utf8Length(value))
                  : '${plural(value.length, 'character')} · '
                        '${formatBytes(utf8Length(value))}',
            ),
            if (store.isSecure) AdminTag.secure(context),
            if (recent) const RecentDot(),
          ],
        ),
      ],
      const SizedBox(height: 8),
    ];

    final Widget body;
    if (value == null) {
      body = _gone(context);
    } else if (hidden) {
      body = EmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'Value hidden',
        message: 'Secure values stay hidden until you choose to see them.',
        action: OutlinedButton.icon(
          key: const ValueKey('jst-value-show'),
          onPressed: () => view.showValues = true,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Show values'),
        ),
      );
    } else if (_editing) {
      body = _editor(context, value, kind!);
    } else {
      body = _viewer(context, value, kind!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        if (value != null && !hidden && !_editing) _actions(context, value),
        if (value != null && !hidden && !_editing) const SizedBox(height: 8),
        Expanded(child: body),
        if (_editing && value != null) ...[
          const SizedBox(height: 8),
          _editActions(),
        ],
      ],
    );
  }

  Widget _gone(BuildContext context) {
    final c = _c;
    final error = c.errorOf(widget.store);
    if (error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '${widget.store.name} can\'t be read',
        message: describeError(error),
      );
    }
    final last = _lastSeen;
    return EmptyState(
      icon: Icons.delete_outline,
      title: '"${widget.entryKey}" holds no value',
      message: 'It was deleted or renamed.',
      action: last == null || c.readOnly
          ? null
          : OutlinedButton.icon(
              key: const ValueKey('jst-value-restore'),
              onPressed: () => runReported(
                context,
                () => c.write(widget.store, widget.entryKey, last),
                success: 'Wrote "${widget.entryKey}" back.',
                failure: 'Could not write it back',
              ),
              icon: const Icon(Icons.restore),
              label: const Text('Write it back'),
            ),
    );
  }

  Widget _actions(BuildContext context, String value) {
    final c = _c;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!c.readOnly)
          FilledButton.tonalIcon(
            key: const ValueKey('jst-value-edit'),
            onPressed: () => _startEdit(value),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        OutlinedButton.icon(
          key: const ValueKey('jst-value-copy'),
          onPressed: () => copyText(context, value, what: 'Value'),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('jst-value-menu'),
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: _menu,
          itemBuilder: (context) => [
            menuItem(context, 'copy-key', Icons.key_outlined, 'Copy key'),
            if (!c.readOnly) ...[
              menuItem(
                context,
                'rename',
                Icons.drive_file_rename_outline,
                'Rename…',
              ),
              menuItem(context, 'duplicate', Icons.copy_all, 'Duplicate…'),
              const PopupMenuDivider(),
              menuItem(
                context,
                'delete',
                Icons.delete_outline,
                'Delete…',
                destructive: true,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _viewer(BuildContext context, String value, ValueKind kind) {
    final cs = Theme.of(context).colorScheme;
    final mono = AdminStyle.mono(context);
    final json = kind.isJson ? checkJson(value).value : null;
    final mode = json == null ? _Mode.text : (_mode ?? _Mode.formatted);
    Widget box(Widget child) => Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );

    final Widget content;
    if (mode == _Mode.tree) {
      content = box(JsonTree(value: json));
    } else if (value.isEmpty) {
      content = box(
        Text(
          'An empty string',
          style: mono.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      final full = mode == _Mode.formatted ? prettyJson(json) : value;
      final cut = !_showAll && full.length > _shownChars;
      content = box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cut)
              MessageBanner(
                message:
                    'Showing the first $_shownChars of ${full.length} '
                    'characters.',
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _showAll = true),
                    child: const Text('Show all'),
                  ),
                ],
                margin: const EdgeInsets.only(bottom: 8),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  cut ? full.substring(0, _shownChars) : full,
                  key: const ValueKey('jst-value-text'),
                  style: mono,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (json != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_Mode>(
              key: const ValueKey('jst-value-mode'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: _Mode.formatted, label: Text('Formatted')),
                ButtonSegment(value: _Mode.tree, label: Text('Tree')),
                ButtonSegment(value: _Mode.text, label: Text('Raw')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(child: content),
      ],
    );
  }

  Widget _editor(BuildContext context, String value, ValueKind kind) {
    final changedSince = _base != null && value != _base;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (changedSince)
            MessageBanner(
              key: const ValueKey('jst-value-conflict'),
              tone: BannerTone.warning,
              message:
                  'This value changed while you were editing. Saving '
                  'replaces it with yours.',
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    _base = value;
                    _edit.text = value;
                  }),
                  child: const Text('Load the new value'),
                ),
                TextButton(
                  onPressed: () => setState(() => _base = value),
                  child: const Text('Keep mine'),
                ),
              ],
              margin: const EdgeInsets.only(bottom: 8),
            ),
          if (_saveError != null)
            MessageBanner(
              message: _saveError!,
              tone: BannerTone.error,
              margin: const EdgeInsets.only(bottom: 8),
            ),
          Expanded(
            child: TextField(
              key: const ValueKey('jst-value-editor'),
              controller: _edit,
              focusNode: _editFocus,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: AdminStyle.mono(context),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'An empty value is a value too.',
              ),
            ),
          ),
          const SizedBox(height: 6),
          valueStatus(_edit.text, wasJson: kind.isJson),
        ],
      ),
    );
  }

  Widget _editActions() {
    final check = checkJson(_edit.text);
    final jsonish = looksLikeJson(_edit.text);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (jsonish) ...[
          TextButton(
            onPressed: check.isValid ? () => _formatEdit(pretty: true) : null,
            child: const Text('Format'),
          ),
          TextButton(
            onPressed: check.isValid ? () => _formatEdit(pretty: false) : null,
            child: const Text('Minify'),
          ),
        ],
        OutlinedButton(
          onPressed: _saving ? null : _cancelEdit,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('jst-value-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
