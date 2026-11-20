/// Adding, renaming, duplicating and deleting entries, and clearing or
/// wiping a whole storage.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';
import '../admin_style.dart';
import '../admin_utils.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';

/// Why [key] can't be a new key of [store]; null when it can.
String? _newKeyProblem(
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) {
  if (key.isEmpty) return 'Enter a key.';
  if (controller.entriesOf(store).containsKey(key)) {
    return '"$key" already holds a value.';
  }
  return null;
}

/// A key like [key] that [store] doesn't hold: `key_copy`, `key_copy2`, …
String _freeKey(
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) {
  final taken = controller.entriesOf(store);
  var candidate = '${key}_copy';
  for (var n = 2; taken.containsKey(candidate); n++) {
    candidate = '${key}_copy$n';
  }
  return candidate;
}

/// Asks for a key and a value and stores them in [store]. Returns the new
/// key, or null when cancelled.
@internal
Future<String?> showNewEntryDialog(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
) => showDialog<String>(
  context: context,
  builder: (_) => _NewEntryDialog(controller: controller, store: store),
);

class _NewEntryDialog extends StatefulWidget {
  const _NewEntryDialog({required this.controller, required this.store});

  final StorageAdminController controller;
  final StorageAdminStore store;

  @override
  State<_NewEntryDialog> createState() => _NewEntryDialogState();
}

class _NewEntryDialogState extends State<_NewEntryDialog> {
  final _key = TextEditingController();
  final _value = TextEditingController();
  bool _tried = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _key.addListener(_changed);
    _value.addListener(_changed);
  }

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  String? get _keyProblem {
    final problem = _newKeyProblem(widget.controller, widget.store, _key.text);
    // An empty key is only worth a word once Add was pressed.
    return _key.text.isEmpty && !_tried ? null : problem;
  }

  Future<void> _add() async {
    setState(() => _tried = true);
    if (_newKeyProblem(widget.controller, widget.store, _key.text) != null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.write(widget.store, _key.text, _value.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not add it: ${describeError(e)}';
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, _key.text);
  }

  void _format() {
    final check = checkJson(_value.text);
    if (check.isValid) _value.text = prettyJson(check.value);
  }

  @override
  Widget build(BuildContext context) {
    final text = _value.text;
    final check = looksLikeJson(text) ? checkJson(text) : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _add,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _add,
      },
      child: AdminDialog(
        title: 'New entry in ${widget.store.name}',
        fill: true,
        width: 620,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('jst-new-entry-add'),
            onPressed: _saving ? null : _add,
            child: Text(_saving ? 'Adding…' : 'Add'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              MessageBanner(
                message: _error!,
                tone: BannerTone.error,
                margin: const EdgeInsets.only(bottom: 12),
              ),
            TextField(
              key: const ValueKey('jst-new-entry-key'),
              controller: _key,
              autofocus: true,
              style: AdminStyle.mono(context, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Key',
                errorText: _keyProblem,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('jst-new-entry-value'),
                controller: _value,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: AdminStyle.mono(context),
                decoration: const InputDecoration(
                  labelText: 'Value',
                  hintText: 'Any text. JSON is checked as you type.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _ValueStatus(text: text, check: check),
                ),
                if (check != null)
                  TextButton.icon(
                    onPressed: check.isValid ? _format : null,
                    icon: const Icon(Icons.format_align_left, size: 16),
                    label: const Text('Format'),
                  ),
              ],
            ),
            if (widget.store.isSecure)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Encrypted with AES-256-GCM where it is kept.',
                  style: AdminStyle.caption(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A line under a value being typed: its size, or what [check] found.
class _ValueStatus extends StatelessWidget {
  const _ValueStatus({required this.text, required this.check});

  final String text;
  final JsonCheck? check;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = check;
    final invalid = c != null && !c.isValid;
    return Text(
      c?.summary ??
          '${plural(text.length, 'character')} · ${formatBytes(utf8Length(text))}',
      key: const ValueKey('jst-value-status'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AdminStyle.caption(
        context,
      ).copyWith(color: invalid ? cs.error : null),
    );
  }
}

/// The status line under an edited value: its size, or what JSON checking
/// found when it looks like JSON or [wasJson].
@internal
Widget valueStatus(String text, {bool wasJson = false}) => _ValueStatus(
  text: text,
  check: wasJson || looksLikeJson(text) ? checkJson(text) : null,
);

/// Asks for a new name for [key] in [store] and renames it. Returns the
/// new key, or null.
@internal
Future<String?> renameEntry(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) async {
  final to = await promptText(
    context,
    title: 'Rename "$key"',
    label: 'New key',
    initial: key,
    monospace: true,
    confirmLabel: 'Rename',
    validate: (text) => text == key
        ? 'That is its key now.'
        : _newKeyProblem(controller, store, text),
  );
  if (to == null || !context.mounted) return null;
  final ok = await runReported(
    context,
    () => controller.rename(store, key, to),
    success: 'Renamed to "$to".',
    failure: 'Could not rename "$key"',
  );
  return ok ? to : null;
}

/// Asks for a key for a copy of [key] in [store] and makes it. Returns the
/// new key, or null.
@internal
Future<String?> duplicateEntry(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  String key,
) async {
  final to = await promptText(
    context,
    title: 'Duplicate "$key"',
    label: 'Key of the copy',
    initial: _freeKey(controller, store, key),
    monospace: true,
    confirmLabel: 'Duplicate',
    validate: (text) => _newKeyProblem(controller, store, text),
  );
  if (to == null || !context.mounted) return null;
  final ok = await runReported(
    context,
    () => controller.copy(store, key, to),
    success: 'Copied to "$to".',
    failure: 'Could not duplicate "$key"',
  );
  return ok ? to : null;
}

/// Asks to delete [keys] from [store] and deletes them. Returns whether it
/// did.
@internal
Future<bool> deleteEntries(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
  Iterable<String> keys,
) async {
  final list = keys.toList();
  if (list.isEmpty) return false;
  final one = list.length == 1;
  final confirmed = await confirmAction(
    context,
    title: one ? 'Delete "${list.single}"?' : 'Delete ${entries(list.length)}?',
    message: one
        ? 'Its value is removed from ${store.name} for good.'
        : 'Their values are removed from ${store.name} for good.',
  );
  if (!confirmed || !context.mounted) return false;
  return runReported(
    context,
    () => controller.delete(store, list),
    success: one
        ? 'Deleted "${list.single}".'
        : 'Deleted ${entries(list.length)}.',
    failure: 'Could not delete',
  );
}

/// Asks to remove every entry of [store] and does. Returns whether it did.
@internal
Future<bool> clearStore(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
) async {
  final unreadable = controller.errorOf(store) is StorageCorruptException;
  final count = controller.entriesOf(store).length;
  final confirmed = await confirmAction(
    context,
    title: 'Clear ${store.name}?',
    message: unreadable
        ? '${store.name} can\'t be read. Clearing it removes what is there '
              'for good and starts over with an empty storage.'
        : 'This removes all ${entries(count)} from ${store.name} for good.',
    confirmLabel: 'Clear',
    typeToConfirm: store.name,
  );
  if (!confirmed || !context.mounted) return false;
  return runReported(
    context,
    () => controller.clear(store),
    success: '${store.name} is empty.',
    failure: 'Could not clear ${store.name}',
  );
}

/// Asks to wipe [store] — empty it and destroy its key — and does. Returns
/// whether it did.
@internal
Future<bool> wipeStore(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
) async {
  final count = controller.entriesOf(store).length;
  final confirmed = await confirmAction(
    context,
    title: 'Wipe ${store.name}?',
    message:
        'This removes ${count == 0 ? 'every entry' : 'all ${entries(count)}'} '
        'and destroys the encryption key: nothing written so far can be '
        'decrypted again, even from a backup or a copy. The next write makes '
        'a new key.',
    confirmLabel: 'Wipe',
    typeToConfirm: store.name,
  );
  if (!confirmed || !context.mounted) return false;
  return runReported(
    context,
    () => controller.wipe(store),
    success: '${store.name} is wiped, its key destroyed.',
    failure: 'Could not wipe ${store.name}',
  );
}
