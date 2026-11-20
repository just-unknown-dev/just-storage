/// One storage's details: how much it holds, of what kinds, where it keeps
/// it and how it is protected — and the actions that remove it all.
@internal
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../../core/admin_types.dart';
import '../../core/core.dart';
import '../../file/admin_support.dart'
    if (dart.library.js_interop) '../../web/admin_support.dart'
    as platform;
import '../admin_style.dart';
import '../admin_utils.dart';
import '../dialogs/entry_dialogs.dart';
import '../dialogs/transfer_dialogs.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';

/// The details of [store].
@internal
class DetailsPane extends StatefulWidget {
  /// The details of [store].
  const DetailsPane({super.key, required this.controller, required this.store});

  /// The screen's state.
  final StorageAdminController controller;

  /// The storage described.
  final StorageAdminStore store;

  @override
  State<DetailsPane> createState() => _DetailsPaneState();
}

class _DetailsPaneState extends State<DetailsPane> {
  Future<StoreDescription?>? _description;
  int? _describedRevision;
  StorageAdminStore? _describedStore;

  /// Asks the platform again when the storage was read since.
  Future<StoreDescription?> _describe() {
    final c = widget.controller;
    final revision = c.revisionOf(widget.store);
    if (_description == null ||
        revision != _describedRevision ||
        widget.store != _describedStore) {
      _describedRevision = revision;
      _describedStore = widget.store;
      final storage = c.storageOf(widget.store);
      _description = storage == null
          ? Future.value()
          : platform.describeStorage(storage).catchError((Object _) => null);
    }
    return _description!;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => FutureBuilder<StoreDescription?>(
        future: _describe(),
        builder: (context, snapshot) => _build(context, snapshot.data),
      ),
    );
  }

  Widget _build(BuildContext context, StoreDescription? description) {
    final c = widget.controller;
    final store = widget.store;
    final cs = Theme.of(context).colorScheme;
    final all = c.entriesOf(store);
    final error = c.errorOf(store);
    var dataBytes = 0;
    MapEntry<String, String>? largest;
    var largestBytes = -1;
    final kinds = <ValueKind, int>{};
    for (final e in all.entries) {
      final bytes = utf8Length(e.value);
      dataBytes += utf8Length(e.key) + bytes;
      if (bytes > largestBytes) {
        largestBytes = bytes;
        largest = e;
      }
      final kind = c.kindOf(store, e.key, e.value);
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    final canWipe = description?.canWipe ?? c.canWipe(store);

    final list = ListView(
      key: ValueKey('jst-details-${store.name}'),
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) ...[
          MessageBanner(
            tone: BannerTone.error,
            message: error is StorageCorruptException
                ? '${store.name} can\'t be read, and is left as it is: '
                      '${describeError(error)}'
                : 'Could not read ${store.name}: ${describeError(error)}',
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            StatTile(
              icon: Icons.list_alt,
              label: 'Entries',
              value: error == null ? '${all.length}' : '—',
            ),
            StatTile(
              icon: Icons.data_usage,
              label: 'Keys and values',
              value: formatBytes(dataBytes),
              tooltip: 'As UTF-8 text',
            ),
            if (description?.sizeBytes case final size?)
              StatTile(
                icon: Icons.sd_storage_outlined,
                label: 'Where kept',
                value: formatBytes(size),
                tooltip: 'What the storage takes where it keeps the values',
              ),
            if (largest != null)
              StatTile(
                icon: Icons.straighten,
                label: 'Largest: ${_short(largest.key)}',
                value: formatBytes(largestBytes),
              ),
          ],
        ),
        if (kinds.isNotEmpty && (!store.isSecure || c.viewOf(store).showValues))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in ValueKind.values)
                  if (kinds[kind] case final n?)
                    AdminTag.neutral(
                      context,
                      '${kind.label}: $n',
                      icon: kind.icon,
                    ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Where the values are',
          children: [
            ListTile(
              leading: Icon(
                store.isSecure
                    ? Icons.lock_outline
                    : Icons.description_outlined,
                color: cs.primary,
              ),
              title: Text(description?.medium ?? 'Kept by the app'),
              subtitle: Text(
                [
                  ?store.description,
                  if (description == null)
                    c.storageOf(store) == null
                        ? 'Not opened yet'
                        : 'A ${c.storageOf(store).runtimeType}: it says no '
                              'more about where it keeps them',
                  if (description?.modified case final at?)
                    'Last saved ${formatDateTime(at)}',
                ].join('\n'),
              ),
            ),
            for (final fact in description?.facts ?? const <StoreFact>[])
              _FactTile(fact: fact),
            const SizedBox(height: 6),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Protection',
          children: [
            ListTile(
              leading: Icon(
                store.isSecure ? Icons.shield_outlined : Icons.lock_open,
                color: store.isSecure ? cs.tertiary : cs.onSurfaceVariant,
              ),
              title: Text(
                store.isSecure ? 'Encrypted with AES-256-GCM' : 'Plain text',
              ),
              subtitle: Text(
                store.isSecure
                    ? 'Each value is sealed on its own and checked when '
                          'read: a changed value makes the storage refuse to '
                          'read rather than return it. This screen hides '
                          'the values until you show them.'
                    : 'Anything that can read where the values are kept '
                          'can read them. Keep tokens and personal data in '
                          'a secure storage.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Backup',
          children: [
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Export as JSON'),
              subtitle: Text(
                store.isSecure
                    ? 'Every entry, decrypted: keep the file safe'
                    : 'Every entry, to copy or save as a file',
              ),
              enabled: error == null && all.isNotEmpty,
              onTap: () => showExportDialog(context, c, store),
            ),
            if (!c.readOnly)
              ListTile(
                key: const ValueKey('jst-details-import'),
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import from JSON'),
                subtitle: const Text(
                  'An export from this screen, or any object of keys and '
                  'values',
                ),
                enabled: error == null,
                onTap: () => showImportDialog(context, c, store),
              ),
          ],
        ),
        if (!c.readOnly) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'Danger zone',
            titleColor: cs.error,
            children: [
              ListTile(
                key: const ValueKey('jst-details-clear'),
                leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
                title: Text('Clear ${store.name}'),
                subtitle: Text(
                  error is StorageCorruptException
                      ? 'It can\'t be read: remove what is there and start '
                            'over'
                      : 'Remove all ${entries(all.length)} for good',
                ),
                enabled: all.isNotEmpty || error is StorageCorruptException,
                onTap: () => clearStore(context, c, store),
              ),
              if (canWipe)
                ListTile(
                  key: const ValueKey('jst-details-wipe'),
                  leading: Icon(Icons.key_off_outlined, color: cs.error),
                  title: Text('Wipe ${store.name}'),
                  subtitle: const Text(
                    'Remove every entry and destroy the key, so no copy or '
                    'backup can be decrypted again',
                  ),
                  onTap: () => wipeStore(context, c, store),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: list,
      ),
    );
  }

  static String _short(String key) =>
      key.length <= 24 ? key : '${key.substring(0, 23)}…';
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final StoreFact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(fact.label, style: AdminStyle.caption(context)),
            ),
          ),
          Expanded(
            child: SelectableText(
              fact.value,
              style: fact.path
                  ? AdminStyle.mono(context, fontSize: 12.5)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (fact.path)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => copyText(context, fact.value, what: fact.label),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}
