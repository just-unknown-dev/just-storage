/// Formatting, value kinds, JSON checks and the export format of the admin
/// screen: no widgets.
@internal
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/material.dart' show IconData, Icons;

import '../core/core.dart';

/// "1 entry", "3 entries": [count] and [word], or [plural] when given.
@internal
String plural(int count, String word, [String? plural]) =>
    '$count ${count == 1 ? word : plural ?? '${word}s'}';

/// "1 entry", "2 entries".
@internal
String entries(int count) => plural(count, 'entry', 'entries');

/// [bytes] as B, KB, MB or GB.
@internal
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}'
      ' ${units[unit]}';
}

/// How many bytes [text] takes as UTF-8, without encoding it.
@internal
int utf8Length(String text) {
  var bytes = 0;
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u < 0x80) {
      bytes += 1;
    } else if (u < 0x800) {
      bytes += 2;
    } else if (u >= 0xD800 &&
        u <= 0xDBFF &&
        i + 1 < units.length &&
        units[i + 1] >= 0xDC00 &&
        units[i + 1] <= 0xDFFF) {
      // A surrogate pair: one 4-byte character.
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/// [time] as `2026-11-20 14:05:09`, in local time.
@internal
String formatDateTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// What [error] says, without the exception's type in front.
@internal
String describeError(Object error) {
  if (error is StorageCorruptException) {
    final which = error.keys.isEmpty
        ? ''
        : ' Keys: ${error.keys.take(8).join(', ')}'
              '${error.keys.length > 8 ? '…' : ''}.';
    return '${error.source} ${error.message}$which';
  }
  if (error is StorageException) {
    final cause = error.cause;
    return cause == null ? error.message : '${error.message} ($cause)';
  }
  if (error is StateError) return error.message;
  if (error is ArgumentError) return '${error.message}';
  if (error is FormatException) return error.message;
  return '$error';
}

// =============================================================================
// Value kinds
// =============================================================================

/// What a stored string looks like.
@internal
enum ValueKind {
  /// An empty string.
  empty('Empty', 'EMPTY', Icons.remove),

  /// `true` or `false`.
  boolean('Boolean', 'BOOL', Icons.toggle_on_outlined),

  /// A JSON number.
  number('Number', 'NUM', Icons.tag),

  /// A JSON object.
  object('JSON object', 'OBJECT', Icons.data_object),

  /// A JSON array.
  array('JSON array', 'ARRAY', Icons.data_array),

  /// Anything else.
  text('Text', 'TEXT', Icons.notes);

  const ValueKind(this.label, this.tag, this.icon);

  /// Its name, for a menu or a tooltip.
  final String label;

  /// Its short name, for a badge.
  final String tag;

  /// Its icon.
  final IconData icon;

  /// Whether it is JSON with structure: an object or an array.
  bool get isJson => this == object || this == array;
}

final _number = RegExp(r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$');

/// What kind of value [value] is. Only text that starts with `{` or `[`
/// is decoded, so most values cost a glance.
@internal
ValueKind kindOf(String value) {
  if (value.isEmpty) return ValueKind.empty;
  if (value == 'true' || value == 'false') return ValueKind.boolean;
  final first = value.codeUnitAt(0);
  if ((first == 0x2D || (first >= 0x30 && first <= 0x39)) &&
      value.length <= 64 &&
      _number.hasMatch(value)) {
    return ValueKind.number;
  }
  final trimmed = value.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return ValueKind.object;
      if (decoded is List) return ValueKind.array;
    } on FormatException {
      // Not JSON: text.
    }
  }
  return ValueKind.text;
}

// =============================================================================
// JSON checks
// =============================================================================

/// What [checkJson] found.
@internal
final class JsonCheck {
  const JsonCheck._(this.value, this.error, this.line, this.column);

  /// The decoded value when [isValid].
  final Object? value;

  /// Why it isn't JSON; null when it is.
  final String? error;

  /// The 1-based line and column of [error], when known.
  final int? line;
  final int? column;

  /// Whether the text is JSON.
  bool get isValid => error == null;

  /// A short description: "JSON object · 3 keys", or the error and where.
  String get summary {
    if (error != null) {
      final at = line == null ? '' : ' (line $line, column $column)';
      return 'Not valid JSON$at: $error';
    }
    final v = value;
    if (v is Map) return 'Valid JSON object · ${plural(v.length, 'key')}';
    if (v is List) return 'Valid JSON array · ${plural(v.length, 'item')}';
    return 'Valid JSON';
  }
}

/// Decodes [text] as JSON and says where it fails.
@internal
JsonCheck checkJson(String text) {
  try {
    return JsonCheck._(jsonDecode(text), null, null, null);
  } on FormatException catch (e) {
    final offset = e.offset;
    if (offset == null || offset < 0 || offset > text.length) {
      return JsonCheck._(null, e.message, null, null);
    }
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return JsonCheck._(null, e.message, line, offset - lineStart + 1);
  }
}

/// Whether [text] looks meant as JSON: it starts with `{` or `[`.
@internal
bool looksLikeJson(String text) {
  final t = text.trimLeft();
  return t.startsWith('{') || t.startsWith('[');
}

/// [value] as indented JSON.
@internal
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

// =============================================================================
// Export and import
// =============================================================================

/// What an export file says it is.
@internal
const String exportFormat = 'just_storage';

/// An export of [entries] from the storage [store]: JSON with the entries
/// under `"entries"`, sorted by key.
@internal
String buildExport({
  required String store,
  required bool secure,
  required Map<String, String> entries,
  DateTime? now,
}) {
  final keys = entries.keys.toList()..sort();
  return prettyJson({
    'format': exportFormat,
    'version': 1,
    'store': store,
    'secure': secure,
    'exported': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'entries': {for (final k in keys) k: entries[k]},
  });
}

/// A file name for an export of [store]: `just_storage-<store>-<time>.json`.
@internal
String exportFileName(String store, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final safe = store
      .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'just_storage-${safe.isEmpty ? 'store' : safe}-'
      '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
}

/// What [parseImport] read.
@internal
final class ImportData {
  const ImportData(
    this.entries, {
    this.converted = 0,
    this.store,
    this.fromSecure = false,
  });

  /// The entries, every value a string.
  final Map<String, String> entries;

  /// How many values weren't strings and are kept as their JSON text.
  final int converted;

  /// The storage the export came from, when it says.
  final String? store;

  /// Whether the export says it came from a secure storage.
  final bool fromSecure;
}

/// Reads [text]: an export this screen made, or any JSON object of keys
/// and values. Values that aren't strings are kept as their JSON text.
/// Throws a [FormatException] saying what is wrong.
@internal
ImportData parseImport(String text) {
  if (text.trim().isEmpty) {
    throw const FormatException('There is nothing to import.');
  }
  final check = checkJson(text);
  if (!check.isValid) throw FormatException(check.summary);
  final decoded = check.value;
  if (decoded is! Map) {
    throw const FormatException(
      'Expected a JSON object of keys and values, or an export of this '
      'screen.',
    );
  }
  Map<Object?, Object?> source = decoded;
  String? store;
  var fromSecure = false;
  if (decoded['format'] == exportFormat) {
    final inner = decoded['entries'];
    if (inner is! Map) {
      throw const FormatException('The export has no "entries" object.');
    }
    source = inner;
    if (decoded['store'] case final String name) store = name;
    fromSecure = decoded['secure'] == true;
  }
  var converted = 0;
  final entries = <String, String>{};
  for (final MapEntry(:key, :value) in source.entries) {
    final k = '$key';
    if (value is String) {
      entries[k] = value;
    } else {
      entries[k] = jsonEncode(value);
      converted++;
    }
  }
  return ImportData(
    entries,
    converted: converted,
    store: store,
    fromSecure: fromSecure,
  );
}

/// How an import treats the keys already there.
@internal
enum ImportMode {
  /// Imported values replace those of the same key; the rest stay.
  merge('Merge, replacing keys that exist'),

  /// Keys that exist keep their values; only new keys are added.
  addNew('Add only keys that are new'),

  /// Everything is removed first.
  replaceAll('Replace everything: clear the storage first');

  const ImportMode(this.label);

  /// What it does, for a radio button.
  final String label;
}
