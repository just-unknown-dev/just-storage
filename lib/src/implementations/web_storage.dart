import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;

import '../just_standard_storage.dart';
import '../models/storage_exception.dart';

/// [JustStandardStorage] implementation for web, backed by the browser's
/// `window.localStorage`.
///
/// All values are stored under keys prefixed with `just_storage:` to avoid
/// collisions with other libraries or the app itself.
///
/// Obtain an instance via the factory:
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// ```
class WebStorage implements JustStandardStorage {
  static const String _prefix = 'just_storage:';

  final Map<String, StreamController<String?>> _controllers = {};

  String _prefixed(String key) => '$_prefix$key';

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

  @override
  Future<String?> read(String key) async {
    return web.window.localStorage.getItem(_prefixed(key));
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      web.window.localStorage.setItem(_prefixed(key), value);
      _emit(key, value);
    } catch (e) {
      throw StorageException('Failed to write key "$key".', cause: e);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      web.window.localStorage.removeItem(_prefixed(key));
      _emit(key, null);
    } catch (e) {
      throw StorageException('Failed to delete key "$key".', cause: e);
    }
  }

  @override
  Future<void> clear() async {
    try {
      final ls = web.window.localStorage;
      final keysToRemove = <String>[];
      for (var i = 0; i < ls.length; i++) {
        final k = ls.key(i);
        if (k != null && k.startsWith(_prefix)) keysToRemove.add(k);
      }
      for (final k in keysToRemove) {
        final shortKey = k.substring(_prefix.length);
        ls.removeItem(k);
        _emit(shortKey, null);
      }
    } catch (e) {
      throw StorageException('Failed to clear storage.', cause: e);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return web.window.localStorage.getItem(_prefixed(key)) != null;
  }

  @override
  Future<Map<String, String>> readAll() async {
    final result = <String, String>{};
    final ls = web.window.localStorage;
    for (var i = 0; i < ls.length; i++) {
      final k = ls.key(i);
      if (k != null && k.startsWith(_prefix)) {
        final v = ls.getItem(k);
        if (v != null) result[k.substring(_prefix.length)] = v;
      }
    }
    return Map.unmodifiable(result);
  }

  @override
  Future<T?> readJson<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    try {
      final raw = web.window.localStorage.getItem(_prefixed(key));
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
    final buffered = <String?>[];
    bool snapshotEmitted = false;

    late StreamController<String?> sc;
    late StreamSubscription<String?> innerSub;

    sc = StreamController<String?>(
      sync: true,
      onListen: () {
        innerSub = _controllerFor(key).stream.listen((value) {
          if (snapshotEmitted) {
            sc.add(value);
          } else {
            buffered.add(value);
          }
        });

        if (!sc.isClosed) {
          sc.add(web.window.localStorage.getItem(_prefixed(key)));
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

  /// Disposes all open stream controllers and releases resources.
  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }
}
