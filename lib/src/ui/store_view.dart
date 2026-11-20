/// How the admin screen shows one storage's entries: search, order, hidden
/// values and the checked keys. Kept per storage, so switching back finds
/// it as it was.
@internal
library;

import 'package:flutter/foundation.dart';

/// The orders the entries can be listed in.
@internal
enum EntrySort {
  /// By key, A to Z.
  keyAscending('Key, A to Z'),

  /// By key, Z to A.
  keyDescending('Key, Z to A'),

  /// Largest values first.
  largest('Largest first'),

  /// Most recently changed first, then by key.
  recent('Recently changed first');

  const EntrySort(this.label);

  /// What it is, for a menu.
  final String label;
}

/// The view of one storage's entries.
@internal
class StoreView extends ChangeNotifier {
  /// A view that hides values when [secure].
  StoreView({required bool secure}) : _showValues = !secure;

  String _query = '';
  bool _showValues;
  EntrySort _sort = EntrySort.keyAscending;
  bool _selecting = false;
  final Set<String> _checked = {};

  /// The search text.
  String get query => _query;
  set query(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  /// Whether values are shown (a secure storage hides them at first).
  bool get showValues => _showValues;
  set showValues(bool value) {
    if (value == _showValues) return;
    _showValues = value;
    notifyListeners();
  }

  /// The order of the entries.
  EntrySort get sort => _sort;
  set sort(EntrySort value) {
    if (value == _sort) return;
    _sort = value;
    notifyListeners();
  }

  /// Whether rows show check boxes on a phone (they always do when wide).
  bool get selecting => _selecting || _checked.isNotEmpty;
  set selecting(bool value) {
    if (value == _selecting && (value || _checked.isEmpty)) return;
    _selecting = value;
    if (!value) _checked.clear();
    notifyListeners();
  }

  /// The checked keys.
  Set<String> get checked => Set.unmodifiable(_checked);

  /// Whether [key] is checked.
  bool isChecked(String key) => _checked.contains(key);

  /// Checks or unchecks [key].
  void toggle(String key) {
    if (!_checked.remove(key)) _checked.add(key);
    notifyListeners();
  }

  /// Checks exactly [keys].
  void checkAll(Iterable<String> keys) {
    _checked
      ..clear()
      ..addAll(keys);
    notifyListeners();
  }

  /// Unchecks every key and leaves selection mode.
  void clearChecked() {
    if (_checked.isEmpty && !_selecting) return;
    _checked.clear();
    _selecting = false;
    notifyListeners();
  }

  /// Forgets checked keys that are no longer in [present].
  void keepOnly(Set<String> present) {
    final before = _checked.length;
    _checked.retainWhere(present.contains);
    if (_checked.length != before) notifyListeners();
  }
}
