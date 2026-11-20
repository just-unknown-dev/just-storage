/// What an app and a workbench connected to it (the just_storage DevTools
/// extension) send each other: the protocol's names, and the JSON forms of
/// storages, changes, descriptions and errors.
@internal
library;

import 'package:flutter/foundation.dart' show internal;

import 'admin_types.dart';
import 'storage_change.dart';
import 'storage_exception.dart';

/// The protocol's version. A workbench refuses an app that speaks another.
@internal
const int workbenchProtocol = 1;

/// The version of just_storage, as the app tells a workbench.
@internal
const String justStorageVersion = '2.0.0';

/// The one service extension an app registers; its parameters are
/// `method` and `args` (a JSON object).
@internal
const String workbenchExtension = 'ext.just_storage.call';

/// The kind of every event an app posts starts with this.
@internal
const String workbenchEventPrefix = 'just_storage.';

/// Event kind: the storages shown changed (one was opened or replaced).
@internal
const String workbenchListEvent = '${workbenchEventPrefix}list';

/// Event kind: a storage changed (`store`, and `changes` in order).
@internal
const String workbenchChangeEvent = '${workbenchEventPrefix}change';

// -----------------------------------------------------------------------------
// Storages
// -----------------------------------------------------------------------------

/// A storage the app shows to workbenches.
@internal
final class WorkbenchStoreInfo {
  /// The storage called [name].
  const WorkbenchStoreInfo({
    required this.name,
    this.description,
    required this.secure,
    required this.canWipe,
    required this.type,
  });

  /// Reads the form written by [toJson].
  factory WorkbenchStoreInfo.fromJson(Map<String, Object?> json) =>
      WorkbenchStoreInfo(
        name: json['name'] as String,
        description: json['description'] as String?,
        secure: json['secure'] == true,
        canWipe: json['canWipe'] == true,
        type: json['type'] as String? ?? 'storage',
      );

  /// What it is called; unique among the app's storages.
  final String name;

  /// A line about what it holds.
  final String? description;

  /// Whether it is a `JustSecureStorage`.
  final bool secure;

  /// Whether it can be wiped: emptied, with its key destroyed.
  final bool canWipe;

  /// Its class in the app.
  final String type;

  /// This storage as JSON.
  Map<String, Object?> toJson() => {
    'name': name,
    'description': ?description,
    'secure': secure,
    'canWipe': canWipe,
    'type': type,
  };
}

// -----------------------------------------------------------------------------
// Changes and descriptions
// -----------------------------------------------------------------------------

/// [change] as JSON.
@internal
Map<String, Object?> encodeChange(StorageChange change) => change.isClear
    ? const {'clear': true}
    : {'key': change.key, 'value': change.value};

/// The change [json] (written by [encodeChange]) stands for.
@internal
StorageChange decodeChange(Map<String, Object?> json) => json['clear'] == true
    ? const StorageChange.cleared()
    : StorageChange(json['key'] as String, json['value'] as String?);

/// [description] as JSON.
@internal
Map<String, Object?> encodeDescription(StoreDescription description) => {
  'medium': description.medium,
  'sizeBytes': ?description.sizeBytes,
  'modified': ?description.modified?.millisecondsSinceEpoch,
  'canWipe': description.canWipe,
  'facts': [
    for (final fact in description.facts)
      {'label': fact.label, 'value': fact.value, 'path': fact.path},
  ],
};

/// The description [json] (written by [encodeDescription]) stands for.
@internal
StoreDescription decodeDescription(Map<String, Object?> json) {
  final modified = json['modified'];
  return StoreDescription(
    medium: json['medium'] as String? ?? 'Kept by the app',
    sizeBytes: json['sizeBytes'] as int?,
    modified: modified is int
        ? DateTime.fromMillisecondsSinceEpoch(modified)
        : null,
    canWipe: json['canWipe'] == true,
    facts: [
      for (final fact in json['facts'] as List? ?? const [])
        if (fact is Map<String, Object?>)
          StoreFact(
            fact['label'] as String? ?? '',
            fact['value'] as String? ?? '',
            path: fact['path'] == true,
          ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

/// [error] as JSON: its kind and what it says, so the workbench shows it as
/// the app would.
@internal
Map<String, Object?> encodeError(Object error) => switch (error) {
  StorageCorruptException() => {
    'type': 'corrupt',
    'source': error.source,
    'message': error.message,
    'keys': error.keys,
    'cause': ?error.cause?.toString(),
  },
  StorageException() => {
    'type': 'storage',
    'message': error.message,
    'cause': ?error.cause?.toString(),
  },
  StateError() => {'type': 'state', 'message': error.message},
  ArgumentError() => {'type': 'argument', 'message': '${error.message}'},
  FormatException() => {'type': 'format', 'message': error.message},
  UnsupportedError() => {
    'type': 'unsupported',
    'message': error.message ?? 'not supported',
  },
  _ => {'type': 'other', 'message': '$error'},
};

/// The error [json] (written by [encodeError]) stands for.
@internal
Object decodeError(Map<String, Object?> json) {
  final message = json['message'] as String? ?? 'the app reported an error';
  final cause = switch (json['cause']) {
    final String text => WorkbenchRemoteError(text),
    _ => null,
  };
  return switch (json['type']) {
    'corrupt' => StorageCorruptException(
      json['source'] as String? ?? 'the storage',
      message,
      keys: [for (final key in json['keys'] as List? ?? const []) '$key'],
      cause: cause,
    ),
    'storage' => StorageException(message, cause: cause),
    'state' => StateError(message),
    'argument' => ArgumentError(message),
    'format' => FormatException(message),
    'unsupported' => UnsupportedError(message),
    _ => WorkbenchRemoteError(message),
  };
}

/// An error the app reported that has no kind of its own here, or the cause
/// of one, as text.
@internal
final class WorkbenchRemoteError implements Exception {
  /// An error that says [message].
  const WorkbenchRemoteError(this.message);

  /// What the app said.
  final String message;

  @override
  String toString() => message;
}
