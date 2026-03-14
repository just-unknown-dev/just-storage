import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../just_standard_storage.dart';
import '../models/storage_exception.dart';

/// [JustStandardStorage] implementation that persists data as plain JSON.
///
/// All data is stored in a flat JSON object in a single file:
/// `<directory>/just_storage.json`.  An in-memory cache avoids repeated
/// file I/O on every read.  Writes are atomic via a rename-swap: the new
/// content is first flushed to `<name>.tmp`, then the tmp file is renamed
/// over the target, which is an atomic OS operation on all supported
/// platforms.
///
/// Obtain an instance via the factory:
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// ```
class FileStorage implements JustStandardStorage {
  /// Creates a [FileStorage] that reads and writes a plain JSON file
  /// inside [_directory].
  ///
  /// Prefer [JustStorage.standard] over calling this constructor directly.
  FileStorage(this._directory);

  final Directory _directory;

  static const String _fileName = 'just_storage.json';

  Map<String, String>? _cache;
  Future<void>? _initFuture;
  final Map<String, StreamController<String?>> _controllers = {};

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  File get _dataFile =>
      File('${_directory.path}${Platform.pathSeparator}$_fileName');

  File get _tmpFile =>
      File('${_directory.path}${Platform.pathSeparator}$_fileName.tmp');

  /// Guards against concurrent initialisation: all callers await the same
  /// Future so `_doInit` body runs exactly once.
  Future<void> _init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    final file = _dataFile;
    if (!await file.exists()) {
      _cache = {};
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cache = decoded.cast<String, String>();
      } else {
        _cache = {};
      }
    } catch (e) {
      // Corrupted file — start with empty store and overwrite on next write.
      _cache = {};
    }
  }

  Future<void> _flush() async {
    await _directory.create(recursive: true);
    final tmp = _tmpFile;
    await tmp.writeAsString(jsonEncode(_cache), flush: true);
    await tmp.rename(_dataFile.path);
  }

  StreamController<String?> _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => StreamController<String?>.broadcast(sync: true),
    );
  }

  void _emit(String key, String? value) {
    if (_controllers.containsKey(key)) {
      _controllers[key]!.add(value);
    }
  }

  // --------------------------------------------------------------------------
  // JustStorage
  // --------------------------------------------------------------------------

  @override
  Future<String?> read(String key) async {
    await _init();
    return _cache![key];
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _init();
      _cache![key] = value;
      await _flush();
      _emit(key, value);
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Failed to write key "$key".', cause: e);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _init();
      _cache!.remove(key);
      await _flush();
      _emit(key, null);
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Failed to delete key "$key".', cause: e);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _init();
      final keys = List<String>.from(_cache!.keys);
      _cache!.clear();
      await _flush();
      for (final k in keys) {
        _emit(k, null);
      }
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Failed to clear storage.', cause: e);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    await _init();
    return _cache!.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    await _init();
    return Map.unmodifiable(_cache!);
  }

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    try {
      await _init();
      final raw = _cache![key];
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw StorageException(
          'Stored value for key "$key" is not a JSON object.',
        );
      }
      return fromJson(decoded);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to read JSON for key "$key".', cause: e);
    }
  }

  @override
  Future<void> writeJson<T>(
    String key,
    T value,
    Map<String, dynamic> Function(T value) toJson,
  ) async {
    try {
      final encoded = jsonEncode(toJson(value));
      await write(key, encoded);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Failed to write JSON for key "$key".', cause: e);
    }
  }

  @override
  Stream<String?> watch(String key) {
    // Events that arrive while the snapshot is still being prepared are
    // buffered and replayed immediately after the snapshot is emitted,
    // preserving causal order.
    final buffered = <String?>[];
    bool snapshotEmitted = false;

    late StreamController<String?> sc;
    late StreamSubscription<String?> innerSub;

    sc = StreamController<String?>(
      sync: true,
      onListen: () async {
        innerSub = _controllerFor(key).stream.listen((value) {
          if (snapshotEmitted) {
            sc.add(value);
          } else {
            buffered.add(value);
          }
        });

        await _init();
        if (!sc.isClosed) {
          sc.add(_cache![key]);
          snapshotEmitted = true;
          for (final v in buffered) {
            sc.add(v);
          }
          buffered.clear();
        }
      },
      onCancel: () => innerSub.cancel(),
    );

    return sc.stream;
  }

  /// Disposes all open stream controllers and releases the in-memory cache.
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
    _cache = null;
  }
}
