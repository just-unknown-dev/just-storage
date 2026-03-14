import 'package:flutter/foundation.dart';

import '../just_secure_storage.dart';
import '../just_standard_storage.dart';
import '../just_storage_factory.dart';

/// State manager for the just_storage admin UI.
///
/// Optionally accepts externally-created storage instances; when omitted, the
/// provider creates its own instances via [JustStorage.standard] and
/// [JustStorage.encrypted] (which resolve to the correct backend for the
/// current platform).
class StorageProvider extends ChangeNotifier {
  StorageProvider({JustStandardStorage? standard, JustSecureStorage? secure})
      : _externalStandard = standard,
        _externalSecure = secure;

  final JustStandardStorage? _externalStandard;
  final JustSecureStorage? _externalSecure;

  JustStandardStorage? _standard;
  JustSecureStorage? _secure;

  Map<String, String> _standardEntries = const {};
  Map<String, String> _secureEntries = const {};
  bool _isLoading = false;
  bool _initialized = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  Map<String, String> get standardEntries => _standardEntries;
  Map<String, String> get secureEntries => _secureEntries;
  bool get isLoading => _isLoading;
  bool get initialized => _initialized;
  String? get error => _error;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Creates storage instances (if not supplied externally) and loads all
  /// entries.  Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _isLoading = true;
    notifyListeners();
    try {
      _standard = _externalStandard ?? await JustStorage.standard();
      _secure = _externalSecure ?? await JustStorage.encrypted();
      await _load();
      _initialized = true;
      _error = null;
    } catch (e) {
      _error = 'Initialization failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-reads all entries from both storages and notifies listeners.
  Future<void> refresh() async {
    if (!_initialized) {
      await init();
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _load();
      _error = null;
    } catch (e) {
      _error = 'Refresh failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Writes [key] → [value] to either the standard or secure store.
  ///
  /// Optimistically updates the in-memory cache before notifying listeners so
  /// the UI reflects the change with zero extra I/O.
  Future<void> writeEntry(
    String key,
    String value, {
    required bool isSecure,
  }) async {
    assert(_initialized, 'Call init() before writing.');
    if (isSecure) {
      await _secure!.write(key, value);
      _secureEntries = Map.unmodifiable({..._secureEntries, key: value});
    } else {
      await _standard!.write(key, value);
      _standardEntries = Map.unmodifiable({..._standardEntries, key: value});
    }
    notifyListeners();
  }

  /// Removes [key] from either the standard or secure store.
  Future<void> deleteEntry(String key, {required bool isSecure}) async {
    assert(_initialized, 'Call init() before deleting.');
    if (isSecure) {
      await _secure!.delete(key);
      _secureEntries = Map.unmodifiable(Map.of(_secureEntries)..remove(key));
    } else {
      await _standard!.delete(key);
      _standardEntries =
          Map.unmodifiable(Map.of(_standardEntries)..remove(key));
    }
    notifyListeners();
  }

  /// Removes all entries from either the standard or secure store.
  Future<void> clearAll({required bool isSecure}) async {
    assert(_initialized, 'Call init() before clearing.');
    _isLoading = true;
    notifyListeners();
    try {
      if (isSecure) {
        await _secure!.clear();
        _secureEntries = const {};
      } else {
        await _standard!.clear();
        _standardEntries = const {};
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to clear: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    final results = await Future.wait<Map<String, String>>([
      _standard!.readAll(),
      _secure!.readAll(),
    ]);
    _standardEntries = Map.unmodifiable(results[0]);
    _secureEntries = Map.unmodifiable(results[1]);
  }
}
