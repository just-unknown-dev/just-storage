/// Exporting entries as JSON (copied, or saved as a file) and importing
/// them (pasted, picked, read from a path, or from an earlier export).
@internal
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../../core/admin_types.dart';
import '../../file/admin_support.dart'
    if (dart.library.js_interop) '../../web/admin_support.dart'
    as platform;
import '../admin_style.dart';
import '../admin_utils.dart';
import '../storage_admin_controller.dart';
import '../widgets/admin_widgets.dart';

/// Exports [store]'s entries — only [keys] when given — as JSON to copy or
/// save.
@internal
Future<void> showExportDialog(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store, {
  Iterable<String>? keys,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ExportDialog(
    store: store,
    count: keys?.length ?? controller.entriesOf(store).length,
    json: controller.exportJson(store, keys: keys),
    hidden: store.isSecure && !controller.viewOf(store).showValues,
  ),
);

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.store,
    required this.count,
    required this.json,
    required this.hidden,
  });

  final StorageAdminStore store;
  final int count;
  final String json;

  /// Whether the preview starts with the values masked, as the screen
  /// shows them.
  final bool hidden;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _saving = false;
  String? _savedTo;
  String? _error;
  late bool _masked = widget.hidden;

  static const int _previewChars = 20000;

  /// The export with every value masked, for a preview of secret values.
  late final String _maskedJson = () {
    final export = jsonDecode(widget.json) as Map<String, dynamic>;
    final entries = export['entries'] as Map<String, dynamic>;
    return prettyJson({
      ...export,
      'entries': {for (final key in entries.keys) key: '••••••••'},
    });
  }();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final where = await platform.saveExport(
        exportFileName(widget.store.name),
        widget.json,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _savedTo = where;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the file: ${describeError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final json = widget.json;
    final shown = _masked ? _maskedJson : json;
    final preview = shown.length > _previewChars
        ? '${shown.substring(0, _previewChars)}\n…'
        : shown;
    return AdminDialog(
      title: 'Export ${widget.store.name}',
      width: 640,
      fill: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('jst-export-copy'),
          onPressed: () => copyText(context, json, what: 'Export'),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton.icon(
          key: const ValueKey('jst-export-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_alt, size: 18),
          label: Text(_saving ? 'Saving…' : 'Save file'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${entries(widget.count)} as JSON · '
            '${formatBytes(utf8Length(json))}. Import it into any storage '
            'from this screen.',
            style: AdminStyle.caption(context),
          ),
          const SizedBox(height: 8),
          if (widget.store.isSecure)
            MessageBanner(
              key: const ValueKey('jst-export-secure-warning'),
              tone: BannerTone.warning,
              message:
                  'The values come out decrypted, in plain text. Keep the '
                  'export somewhere safe, and delete it when you are done.',
              actions: [
                if (_masked)
                  TextButton(
                    key: const ValueKey('jst-export-show'),
                    onPressed: () => setState(() => _masked = false),
                    child: const Text('Show them here'),
                  ),
              ],
              margin: const EdgeInsets.only(bottom: 8),
            ),
          if (_savedTo != null)
            MessageBanner(
              key: const ValueKey('jst-export-saved'),
              message: 'Saved to $_savedTo',
              actions: [
                TextButton(
                  onPressed: () =>
                      copyText(context, _savedTo!, what: 'Location'),
                  child: const Text('Copy location'),
                ),
              ],
              margin: const EdgeInsets.only(bottom: 8),
            ),
          if (_error != null)
            MessageBanner(
              message: _error!,
              tone: BannerTone.error,
              margin: const EdgeInsets.only(bottom: 8),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview,
                  key: const ValueKey('jst-export-text'),
                  style: AdminStyle.mono(context, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Imports entries into [store] from JSON: pasted, picked, read from a
/// path or from an earlier export.
@internal
Future<void> showImportDialog(
  BuildContext context,
  StorageAdminController controller,
  StorageAdminStore store,
) => showDialog<void>(
  context: context,
  builder: (_) => _ImportDialog(controller: controller, store: store),
);

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.controller, required this.store});

  final StorageAdminController controller;
  final StorageAdminStore store;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();
  ImportMode _mode = ImportMode.merge;
  ImportData? _data;
  String? _problem;
  String? _source;
  bool _importing = false;
  Future<List<ExportFile>>? _exports;
  Timer? _parseTimer;

  @override
  void initState() {
    super.initState();
    _text.addListener(_scheduleParse);
    if (!platform.canPickFiles) {
      _exports = platform.listExports().catchError((Object _) {
        return const <ExportFile>[];
      });
    }
  }

  @override
  void dispose() {
    _parseTimer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _scheduleParse() {
    _parseTimer?.cancel();
    _parseTimer = Timer(const Duration(milliseconds: 150), _parse);
  }

  void _parse() {
    if (!mounted) return;
    final text = _text.text;
    setState(() {
      if (text.trim().isEmpty) {
        _data = null;
        _problem = null;
        return;
      }
      try {
        _data = parseImport(text);
        _problem = null;
      } on FormatException catch (e) {
        _data = null;
        _problem = e.message;
      }
    });
  }

  void _load(String name, String content) {
    _source = name;
    _text.text = content;
    _parseTimer?.cancel();
    _parse();
  }

  Future<void> _pick() async {
    try {
      final picked = await platform.pickTextFile();
      if (picked != null && mounted) _load(picked.name, picked.content);
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    }
  }

  Future<void> _readPath(String path) async {
    try {
      final content = await platform.readExport(path);
      if (mounted) _load(path, content);
    } catch (e) {
      if (mounted) {
        setState(() => _problem = 'Could not read $path: ${describeError(e)}');
      }
    }
  }

  Future<void> _askPath() async {
    final path = await promptText(
      context,
      title: 'Read a file',
      label: 'Path of a JSON file',
      monospace: true,
      confirmLabel: 'Read',
      validate: (t) => t.trim().isEmpty ? 'Enter a path.' : null,
    );
    if (path != null) await _readPath(path.trim());
  }

  Future<void> _import() async {
    final data = _data;
    if (data == null || data.entries.isEmpty) return;
    final c = widget.controller;
    final store = widget.store;
    if (_mode == ImportMode.replaceAll) {
      final count = c.entriesOf(store).length;
      final ok = await confirmAction(
        context,
        title: 'Replace everything in ${store.name}?',
        message:
            'All ${entries(count)} now in ${store.name} are removed first, '
            'for good.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _importing = true);
    int written;
    try {
      written = await c.importEntries(
        store,
        data.entries,
        replaceExisting: _mode != ImportMode.addNew,
        clearFirst: _mode == ImportMode.replaceAll,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _problem = 'The import failed: ${describeError(e)}';
        });
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showAdminMessage(
      context,
      'Imported ${entries(written)} into ${store.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = widget.store;
    final data = _data;
    final existing = widget.controller.entriesOf(store);
    final already = data == null
        ? 0
        : data.entries.keys.where(existing.containsKey).length;
    final count = data?.entries.length ?? 0;
    final fresh = count - already;
    final writes = switch (_mode) {
      ImportMode.merge || ImportMode.replaceAll => count,
      ImportMode.addNew => fresh,
    };

    return AdminDialog(
      title: 'Import into ${store.name}',
      width: 680,
      fill: true,
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('jst-import-run'),
          onPressed: _importing || data == null || writes == 0 ? null : _import,
          child: Text(
            _importing
                ? 'Importing…'
                : writes == 0
                ? 'Import'
                : 'Import ${entries(writes)}',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (platform.canPickFiles)
                OutlinedButton.icon(
                  key: const ValueKey('jst-import-pick'),
                  onPressed: _pick,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Choose a file…'),
                ),
              if (platform.canReadTypedPaths)
                OutlinedButton.icon(
                  key: const ValueKey('jst-import-path'),
                  onPressed: _askPath,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Read a path…'),
                ),
              if (_exports != null)
                FutureBuilder<List<ExportFile>>(
                  future: _exports,
                  builder: (context, snapshot) {
                    final files = snapshot.data ?? const <ExportFile>[];
                    return PopupMenuButton<ExportFile>(
                      key: const ValueKey('jst-import-saved'),
                      enabled: files.isNotEmpty,
                      tooltip: files.isEmpty
                          ? 'No exports saved yet'
                          : 'Exports saved from this screen',
                      onSelected: (f) => _readPath(f.path),
                      itemBuilder: (context) => [
                        for (final f in files.take(30))
                          PopupMenuItem(
                            value: f,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(f.name),
                              subtitle: Text(
                                '${formatDateTime(f.modified)} · '
                                '${formatBytes(f.sizeBytes)}',
                              ),
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history,
                              size: 18,
                              color: files.isEmpty
                                  ? cs.onSurface.withValues(alpha: 0.38)
                                  : cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              files.isEmpty
                                  ? 'No saved exports'
                                  : 'Saved exports (${files.length})',
                              style: TextStyle(
                                color: files.isEmpty
                                    ? cs.onSurface.withValues(alpha: 0.38)
                                    : cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('jst-import-text'),
              controller: _text,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: AdminStyle.mono(context, fontSize: 12),
              decoration: InputDecoration(
                labelText: _source == null ? 'JSON' : 'JSON from $_source',
                hintText:
                    'Paste an export from this screen, or any JSON object '
                    'of keys and values: {"theme": "dark", "volume": "0.8"}',
                hintMaxLines: 3,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_problem != null)
            Text(
              _problem!,
              key: const ValueKey('jst-import-problem'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AdminStyle.caption(context).copyWith(color: cs.error),
            )
          else if (data != null) ...[
            Text(
              [
                '${entries(count)}: $fresh new, $already already in '
                    '${store.name}',
                if (data.converted > 0)
                  '${data.converted} not text, kept as their JSON',
                if (data.store != null) 'exported from ${data.store}',
              ].join(' · '),
              key: const ValueKey('jst-import-summary'),
              style: AdminStyle.caption(context),
            ),
            if (!store.isSecure && data.fromSecure)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: MessageBanner(
                  tone: BannerTone.warning,
                  message:
                      'These came from an encrypted storage; this one keeps '
                      'values in plain text.',
                ),
              ),
          ],
          const SizedBox(height: 10),
          SegmentedButton<ImportMode>(
            key: const ValueKey('jst-import-mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ImportMode.merge, label: Text('Merge')),
              ButtonSegment(
                value: ImportMode.addNew,
                label: Text('Only new keys'),
              ),
              ButtonSegment(
                value: ImportMode.replaceAll,
                label: Text('Replace all'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 4),
          Text(_mode.label, style: AdminStyle.caption(context)),
        ],
      ),
    );
  }
}
