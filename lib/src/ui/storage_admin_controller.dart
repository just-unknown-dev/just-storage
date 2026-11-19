import 'package:flutter/foundation.dart';

import '../core/core.dart';
import '../file/file.dart' if (dart.library.js_interop) '../web/web.dart';
import 'just_storage_admin_screen.dart';

/// What [JustStorageAdminScreen] shows: the entries of a standard and a
/// secure storage, and what went wrong reading each.
///
/// The two are read separately: a secure storage that can't be read (a
/// [StorageCorruptException]) still leaves the standard one to look at, and
/// can be cleared from the screen to start over.
class StorageAdminController extends ChangeNotifier {
  /// A controller over [standard] and [secure]; each one left out is
  /// opened with [JustStorage.standard] or [JustStorage.encrypted].
  StorageAdminController({
    JustStandardStorage? standard,
    JustSecureStorage? secure,
  }) : _givenStandard = standard,
       _givenSecure = secure;

  final JustStandardStorage? _givenStandard;
  final JustSecureStorage? _givenSecure;

  JustStandardStorage? _standard;
  JustSecureStorage? _secure;

  Map<String, String> _standardEntries = const {};
  Map<String, String> _secureEntries = const {};
  Object? _standardError;
  Object? _secureError;
  bool _loading = false;
  bool _loaded = false;
  bool _disposed = false;

  /// The entries of the secure storage when [secure], else of the standard
  /// one, as last read.
  Map<String, String> entries({required bool secure}) =>
      secure ? _secureEntries : _standardEntries;

  /// What went wrong reading the secure storage when [secure], else the
  /// standard one; `null` when it was read.
  Object? error({required bool secure}) =>
      secure ? _secureError : _standardError;

  /// Whether a read is under way.
  bool get isLoading => _loading;

  /// Whether both storages have been read once, or failed to be.
  bool get loaded => _loaded;

  /// Reads both storages again.
  Future<void> refresh() async {
    _loading = true;
    _notify();
    await Future.wait([_read(secure: false), _read(secure: true)]);
    _loading = false;
    _loaded = true;
    _notify();
  }

  /// Stores [value] under [key] in the secure storage when [secure], else
  /// in the standard one. Throws what the storage throws.
  Future<void> writeEntry(
    String key,
    String value, {
    required bool secure,
  }) async {
    await (await _storage(secure: secure)).write(key, value);
    await _read(secure: secure);
    _notify();
  }

  /// Removes [key] from the secure storage when [secure], else from the
  /// standard one. Throws what the storage throws.
  Future<void> deleteEntry(String key, {required bool secure}) async {
    await (await _storage(secure: secure)).delete(key);
    await _read(secure: secure);
    _notify();
  }

  /// Removes every entry of the secure storage when [secure], else of the
  /// standard one — one that can't be read, too. Throws what the storage
  /// throws.
  Future<void> clearAll({required bool secure}) async {
    try {
      await (await _storage(secure: secure)).clear();
    } finally {
      await _read(secure: secure);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<JustKeyValueStorage> _storage({required bool secure}) async {
    if (secure) {
      return _secure ??= _givenSecure ?? await JustStorage.encrypted();
    }
    return _standard ??= _givenStandard ?? await JustStorage.standard();
  }

  Future<void> _read({required bool secure}) async {
    Map<String, String> entries;
    Object? error;
    try {
      entries = await (await _storage(secure: secure)).readAll();
    } catch (e) {
      entries = const {};
      error = e;
    }
    if (secure) {
      _secureEntries = entries;
      _secureError = error;
    } else {
      _standardEntries = entries;
      _standardError = error;
    }
  }

  /// Tells listeners, unless the screen has gone: a read can finish after
  /// it closes.
  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
