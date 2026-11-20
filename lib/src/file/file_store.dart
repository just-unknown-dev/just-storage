import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show internal;

import '../core/core.dart';
import '../core/value_watchers.dart';
import 'atomic_file.dart';

/// How a [FileStore] turns its entries into the file's text and back.
@internal
abstract interface class FileStoreCodec {
  /// The entries [text] holds. [path] is the file's, for messages.
  ///
  /// Throws a [StorageCorruptException] when [text] isn't what [encode]
  /// writes, and leaves the file alone.
  Future<Map<String, String>> decode(String text, String path);

  /// The file's text for [entries].
  Future<String> encode(Map<String, String> entries);

  /// Forgets what it learnt from the file, for a storage that is being
  /// cleared: [unreadable] when the file couldn't be read, [wipe] when
  /// nothing written before may be readable afterwards. Never runs during
  /// [encode].
  Future<void> forget({required bool unreadable, required bool wipe});

  /// Whether the file it read should be written again, in the format
  /// [encode] writes now.
  bool get wantsRewrite;
}

/// One file of entries, as [FileStorage] and [EncryptedFileStorage] keep
/// them: read once into memory, written back whole after every change.
///
/// * Writes are saved one at a time. Writes made while a save is under way
///   share the next one, so a burst of them costs two saves, not one each.
/// * A write's future completes once a save holding it has finished. When
///   that save fails, the keys it held are put back to what the file holds,
///   and the write throws a [StorageException].
/// * Each save writes a temporary file and renames it over the file, so a
///   crash leaves the old file or the new one, never half of one.
/// * A file that can't be read throws a [StorageCorruptException] and is
///   never written over, except by [clear].
@internal
final class FileStore {
  /// The store kept in [directory]/[fileName], written by [codec].
  FileStore(this.directory, this.fileName, this.codec);

  /// The folder the file is in.
  final Directory directory;

  /// The file's name.
  final String fileName;

  /// Turns entries into the file's text and back.
  final FileStoreCodec codec;

  /// The file.
  late final File file = File(
    '${directory.path}${Platform.pathSeparator}$fileName',
  );

  final ValueWatchers _watchers = ValueWatchers();
  final ChangeListeners _changeListeners = ChangeListeners();

  /// The entries as callers see them: every write so far, saved or not.
  Map<String, String>? _cache;

  /// The entries as the file holds them: what was read, or last saved.
  Map<String, String> _onDisk = const {};

  Future<void>? _loading;

  /// The end of the chain of saves; it never fails.
  Future<void> _saves = Future.value();

  /// The save not yet started that new writes join.
  Completer<void>? _nextSave;

  /// Saves scheduled and not finished.
  int _pendingSaves = 0;

  /// Writes, deletes and clears called and not finished, for [dispose].
  final Set<Future<void>> _changes = {};

  Future<void> _tracked(Future<void> change) {
    _changes.add(change);
    change.whenComplete(() {
      _changes.remove(change);
    }).ignore();
    return change;
  }

  /// The entries, read from the file the first time.
  Future<Map<String, String>> _entries() async {
    final cache = _cache;
    if (cache != null) return cache;
    final loading = _loading ??= _load();
    try {
      await loading;
    } catch (_) {
      // Read again next time: the file may have been put right.
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
    return _cache!;
  }

  Future<void> _load() async {
    await AtomicFile.sweep(file);
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on PathNotFoundException {
      _onDisk = const {};
      _cache = {};
      return;
    } on FileSystemException catch (e) {
      throw StorageException('Could not read ${file.path}.', cause: e);
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (e) {
      throw StorageCorruptException(file.path, 'is not UTF-8 text.', cause: e);
    }
    final entries = await codec.decode(text, file.path);
    _onDisk = Map.of(entries);
    _cache = entries;
    if (codec.wantsRewrite) {
      // Bring an old format forward now; if it fails, the next write will.
      unawaited(_save().catchError((Object _) {}));
    }
  }

  /// The value of [key].
  Future<String?> read(String key) async => (await _entries())[key];

  /// Whether [key] holds a value.
  Future<bool> containsKey(String key) async =>
      (await _entries()).containsKey(key);

  /// A copy of every entry.
  Future<Map<String, String>> readAll() async =>
      Map.unmodifiable(await _entries());

  /// The entries, as the map the next save will read: if [dispose] ran
  /// while they were being fetched, they are fetched again.
  Future<Map<String, String>> _liveEntries() async {
    while (true) {
      final entries = await _entries();
      if (identical(entries, _cache)) return entries;
    }
  }

  /// Stores [value] under [key] and saves it.
  Future<void> write(String key, String value) => _tracked(_write(key, value));

  Future<void> _write(String key, String value) async {
    final entries = await _liveEntries();
    if (entries[key] == value && _onDisk[key] == value && _pendingSaves == 0) {
      // The file holds it already: nothing to save.
      _watchers.changed(key, value);
      return;
    }
    entries[key] = value;
    await _saveAs('Could not save "$key"');
    _watchers.changed(key, value);
    _changeListeners.add(StorageChange(key, value));
  }

  /// Removes [key] and saves.
  Future<void> delete(String key) => _tracked(_delete(key));

  Future<void> _delete(String key) async {
    final entries = await _liveEntries();
    if (!entries.containsKey(key) &&
        !_onDisk.containsKey(key) &&
        _pendingSaves == 0) {
      return;
    }
    entries.remove(key);
    await _saveAs('Could not delete "$key"');
    _watchers.changed(key, null);
    _changeListeners.add(StorageChange(key, null));
  }

  /// Removes every entry and saves an empty store — over a file that can't
  /// be read, too. With [wipe], the codec forgets everything that could read
  /// what was written before.
  Future<void> clear({bool wipe = false}) => _tracked(_clear(wipe));

  Future<void> _clear(bool wipe) async {
    Map<String, String> entries;
    var unreadable = false;
    try {
      entries = await _liveEntries();
    } on StorageCorruptException {
      // Starting over is what clearing is for.
      unreadable = true;
      entries = _cache = {};
      _loading = null;
    }
    final cleared = {...entries.keys, ..._watchers.keys};
    entries.clear();
    // Between saves, so it never runs while one is encoding.
    final forgotten = _saves.then(
      (_) => codec.forget(unreadable: unreadable, wipe: wipe),
    );
    _saves = forgotten.then((_) {}, onError: (Object _) {});
    try {
      await forgotten;
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not clear ${file.path}.', cause: e);
    }
    await _saveAs('Could not clear the store');
    for (final key in cleared) {
      _watchers.changed(key, null);
    }
    _changeListeners.add(const StorageChange.cleared());
  }

  /// The values of [key], as [JustKeyValueStorage.watch] describes.
  Stream<String?> watch(String key) =>
      _watchers.watch(key, load: _entries, now: () => _cache?[key]);

  /// Every saved change, as [JustKeyValueStorage.changes] describes.
  Stream<StorageChange> get changes => _changeListeners.stream;

  /// Waits for the writes, deletes and clears called so far and their
  /// saves, then ends every watch stream and forgets the entries; the next
  /// call reads the file again.
  Future<void> dispose() async {
    // What starts while waiting is waited for too.
    while (true) {
      final saves = _saves;
      final changes = [..._changes];
      await Future.wait([
        for (final change in changes) change.then((_) {}, onError: (_) {}),
        saves,
      ]);
      if (_changes.isEmpty && identical(saves, _saves)) break;
    }
    _watchers.closeAll();
    _changeListeners.closeAll();
    _cache = null;
    _onDisk = const {};
    _loading = null;
  }

  Future<void> _saveAs(String failure) async {
    try {
      await _save();
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        '$failure: ${file.path} was not written.',
        cause: e,
      );
    }
  }

  /// Saves the entries as they are when the save starts. Joins the save
  /// not yet started, if there is one.
  Future<void> _save() {
    final next = _nextSave;
    if (next != null) return next.future;
    final done = _nextSave = Completer<void>();
    _pendingSaves++;
    _saves = _saves.then((_) => _runSave(done));
    return done.future;
  }

  Future<void> _runSave(Completer<void> done) async {
    if (identical(_nextSave, done)) _nextSave = null;
    try {
      final entries = _cache;
      if (entries == null) {
        // Disposed and not read since: there is nothing to save.
        done.complete();
        return;
      }
      final saving = Map.of(entries);
      try {
        final text = await codec.encode(saving);
        await AtomicFile.write(file, utf8.encode(text));
      } catch (e, s) {
        _revert(saving);
        done.completeError(e, s);
        return;
      }
      _onDisk = saving;
      done.complete();
    } finally {
      _pendingSaves--;
    }
  }

  /// Puts the keys a failed save held back to what the file holds — those
  /// that haven't changed again since, which their own save will settle.
  void _revert(Map<String, String> tried) {
    final entries = _cache;
    if (entries == null) return;
    for (final key in {...tried.keys, ..._onDisk.keys}) {
      final attempted = tried[key];
      if (entries[key] != attempted) continue;
      final saved = _onDisk[key];
      if (saved == attempted) continue;
      if (saved == null) {
        entries.remove(key);
      } else {
        entries[key] = saved;
      }
    }
  }
}
