import 'package:flutter/foundation.dart' show immutable;

import 'just_key_value_storage.dart';

/// One change to a [JustKeyValueStorage], from its
/// [JustKeyValueStorage.changes] stream: a key written or deleted, or every
/// key removed at once.
///
/// ```dart
/// storage.changes.listen((change) {
///   if (change.isClear) {
///     print('everything was removed');
///   } else if (change.isDelete) {
///     print('${change.key} was deleted');
///   } else {
///     print('${change.key} is now ${change.value}');
///   }
/// });
/// ```
@immutable
final class StorageChange {
  /// [key] now holds [value]; a `null` [value] means it was deleted.
  const StorageChange(String this.key, this.value);

  /// Every key was removed: [JustKeyValueStorage.clear], or the browser's
  /// storage cleared from another tab.
  const StorageChange.cleared() : key = null, value = null;

  /// The key that changed; `null` when every key was removed.
  final String? key;

  /// What [key] holds now; `null` when it was deleted, and for a clear.
  final String? value;

  /// Whether every key was removed at once.
  bool get isClear => key == null;

  /// Whether [key] was deleted.
  bool get isDelete => key != null && value == null;

  @override
  bool operator ==(Object other) =>
      other is StorageChange && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  /// Names the key and what happened to it, never the value: a secure
  /// storage's values don't belong in logs.
  @override
  String toString() => isClear
      ? 'StorageChange.cleared()'
      : 'StorageChange("$key" ${isDelete ? 'deleted' : 'written'})';
}
