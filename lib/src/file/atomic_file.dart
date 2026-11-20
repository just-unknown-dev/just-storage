import 'dart:io';

import 'package:flutter/foundation.dart' show internal, visibleForTesting;

/// Writes a file so that a reader, or a crash, never sees half of it: the
/// bytes go to a temporary file beside it, which is then renamed over it.
@internal
abstract final class AtomicFile {
  static int _temps = 0;

  /// How many writes have started in this process, for tests that count
  /// saves.
  @visibleForTesting
  static int get writesStarted => _temps;

  /// The prefix of [target]'s temporary files.
  static String tempPrefix(File target) => '${target.path}.tmp.';

  /// Replaces [target]'s contents with [bytes].
  ///
  /// [prepare] runs on the temporary file once it holds the bytes, before
  /// the rename: to narrow its permissions, say, so the file never exists
  /// under its own name with wider ones. Its folder is made if it is
  /// missing. On Windows, where a file another program has open can't be
  /// replaced, the rename is tried again for a moment before it fails.
  static Future<void> write(
    File target,
    List<int> bytes, {
    Future<void> Function(File temp)? prepare,
  }) async {
    await target.parent.create(recursive: true);
    // Unique per process and per write, so two writers never share one.
    final temp = File('${tempPrefix(target)}$pid.${_temps++}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (prepare != null) await prepare(temp);
      await _renameOver(temp, target);
    } catch (_) {
      try {
        await temp.delete();
      } on FileSystemException {
        // Already gone, or never made.
      }
      rethrow;
    }
  }

  static Future<void> _renameOver(File from, File to) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await from.rename(to.path);
        return;
      } on FileSystemException {
        if (!Platform.isWindows || attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 10 << attempt));
      }
    }
  }

  /// Deletes temporary files of [target] left behind by a write that never
  /// finished — a crash, a killed process — once they are older than
  /// [olderThan], so a write still under way elsewhere keeps its own.
  static Future<void> sweep(
    File target, {
    Duration olderThan = const Duration(minutes: 1),
  }) async {
    final prefix = '${_name(target)}.tmp.';
    final cutoff = DateTime.now().subtract(olderThan);
    try {
      await for (final entity in target.parent.list(followLinks: false)) {
        if (entity is! File || !_name(entity).startsWith(prefix)) continue;
        try {
          if ((await entity.lastModified()).isBefore(cutoff)) {
            await entity.delete();
          }
        } on FileSystemException {
          // In use, or gone already: leave it.
        }
      }
    } on FileSystemException {
      // No folder yet, or it can't be listed: nothing to sweep.
    }
  }

  static String _name(FileSystemEntity entity) =>
      entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
}
