/// What the admin screen learns from the platform about a storage and about
/// export files — shared by file/ and web/, not exported.
@internal
library;

import 'package:flutter/foundation.dart' show internal;

/// Where and how a storage keeps its values, as the platform can tell.
@internal
final class StoreDescription {
  /// A description of a storage kept in [medium].
  const StoreDescription({
    required this.medium,
    this.sizeBytes,
    this.modified,
    this.facts = const [],
    this.canWipe = false,
  });

  /// What holds the values: a file, an encrypted file, browser storage.
  final String medium;

  /// How many bytes the values take where they are kept; null when unknown
  /// or nothing is kept yet.
  final int? sizeBytes;

  /// When the values were last saved; null when unknown.
  final DateTime? modified;

  /// Details, in the order to show them.
  final List<StoreFact> facts;

  /// Whether the storage can be wiped: emptied, and its key destroyed.
  final bool canWipe;
}

/// One detail of a [StoreDescription].
@internal
final class StoreFact {
  /// [label]: [value]; a [path] is shown in monospace with a copy button.
  const StoreFact(this.label, this.value, {this.path = false});

  /// What the detail is.
  final String label;

  /// The detail.
  final String value;

  /// Whether [value] is a path or a name to copy.
  final bool path;
}

/// An export file the admin screen saved earlier.
@internal
final class ExportFile {
  /// An entry for the file [name] at [path].
  const ExportFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });

  /// The file name.
  final String name;

  /// Where it is.
  final String path;

  /// Its size in bytes.
  final int sizeBytes;

  /// When it was last written.
  final DateTime modified;
}

/// A text file the user picked: its name and what it holds.
@internal
typedef PickedTextFile = ({String name, String content});
