/// A decoded JSON value as a tree of rows that open and close.
@internal
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart';

import '../admin_style.dart';
import 'admin_widgets.dart';

/// [value] — decoded JSON — as a tree: objects and arrays open and close,
/// the first two levels open at the start. Only the rows on screen are
/// built, so a large value stays quick. A long press copies a node.
@internal
class JsonTree extends StatefulWidget {
  /// A tree of [value].
  const JsonTree({super.key, required this.value});

  /// The decoded JSON.
  final Object? value;

  @override
  State<JsonTree> createState() => _JsonTreeState();
}

class _JsonTreeState extends State<JsonTree> {
  /// Containers deeper than this start closed.
  int _openDepth = 2;

  /// Paths opened or closed by hand, against [_openDepth].
  final Set<String> _flipped = {};

  /// The most children of one container listed.
  static const int _limit = 500;

  @override
  void didUpdateWidget(JsonTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _flipped.clear();
  }

  bool _isOpen(String path, int depth) =>
      (depth < _openDepth) != _flipped.contains(path);

  List<_Row> _rows() {
    final rows = <_Row>[];
    void visit(String? label, bool index, Object? value, String path, int d) {
      final container = value is Map || value is List;
      final open = container && _isOpen(path, d);
      rows.add(_Row(label, index, value, path, d, open: open));
      if (!open) return;
      if (value is Map) {
        var n = 0;
        for (final MapEntry(key: k, value: v) in value.entries) {
          if (n++ == _limit) {
            rows.add(_Row.more(value.length - _limit, d + 1));
            break;
          }
          visit('$k', false, v, '$path\u0000$k', d + 1);
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          if (i == _limit) {
            rows.add(_Row.more(value.length - _limit, d + 1));
            break;
          }
          visit('$i', true, value[i], '$path\u0000$i', d + 1);
        }
      }
    }

    visit(null, false, widget.value, '', 0);
    return rows;
  }

  void _setAll(bool open) => setState(() {
    _openDepth = open ? 1 << 20 : 1;
    _flipped.clear();
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const ValueKey('jst-tree-expand'),
              tooltip: 'Expand all',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setAll(true),
              icon: const Icon(Icons.unfold_more, size: 18),
            ),
            IconButton(
              tooltip: 'Collapse all',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setAll(false),
              icon: const Icon(Icons.unfold_less, size: 18),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('jst-tree'),
            itemCount: rows.length,
            itemExtent: 26,
            itemBuilder: (context, i) => _RowView(
              row: rows[i],
              onToggle: () => setState(() {
                final path = rows[i].path;
                if (!_flipped.remove(path)) _flipped.add(path);
              }),
            ),
          ),
        ),
      ],
    );
  }
}

final class _Row {
  _Row(
    this.label,
    this.isIndex,
    this.value,
    this.path,
    this.depth, {
    required this.open,
  }) : more = 0;

  _Row.more(this.more, this.depth)
    : label = null,
      isIndex = false,
      value = null,
      path = '',
      open = false;

  final String? label;
  final bool isIndex;
  final Object? value;
  final String path;
  final int depth;
  final bool open;

  /// For a "… N more" row: how many children are not listed.
  final int more;

  bool get isContainer => value is Map || value is List;
}

class _RowView extends StatelessWidget {
  const _RowView({required this.row, required this.onToggle});

  final _Row row;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = AdminStyle.mono(context, fontSize: 12.5, height: 1.2);
    final indent = 8.0 + row.depth * 16;
    if (row.more > 0) {
      return Padding(
        padding: EdgeInsets.only(left: indent + 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '… ${row.more} more',
            style: mono.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final value = row.value;
    final (String shown, Color color) = switch (value) {
      Map() => (
        row.open
            ? '{'
            : '{…} ${value.length} ${value.length == 1 ? 'key' : 'keys'}',
        cs.onSurfaceVariant,
      ),
      List() => (
        row.open
            ? '['
            : '[…] ${value.length} ${value.length == 1 ? 'item' : 'items'}',
        cs.onSurfaceVariant,
      ),
      String() => (jsonEncode(value), cs.tertiary),
      num() => ('$value', cs.secondary),
      bool() => ('$value', cs.primary),
      null => ('null', cs.onSurfaceVariant),
      _ => ('$value', cs.onSurface),
    };
    return InkWell(
      onTap: row.isContainer ? onToggle : null,
      onLongPress: () => copyText(
        context,
        value is String ? value : jsonEncode(value),
        what: row.label == null ? 'Value' : '"${row.label}"',
      ),
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: row.isContainer
                  ? Icon(
                      row.open ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    )
                  : null,
            ),
            if (row.label != null)
              Text(
                row.isIndex ? '${row.label}: ' : '"${row.label}": ',
                style: mono.copyWith(
                  color: row.isIndex ? cs.onSurfaceVariant : cs.onSurface,
                  fontWeight: row.isIndex ? null : FontWeight.w600,
                ),
              ),
            Expanded(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
