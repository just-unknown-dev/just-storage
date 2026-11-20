import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/core.dart';
import '../core/workbench_service.dart';
import 'admin_support.dart' as admin;
import 'encrypted_file_storage.dart';
import 'file_storage.dart';

/// Opens the storages, on native platforms.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
///
/// Every call for one folder hands back the **same** instance. A storage
/// keeps its whole file in memory and writes it back whole, so two
/// instances over one folder would each write over the other's keys.
/// Because the instance is shared, disposing it affects everyone using it.
///
/// Without a folder, the app's support directory
/// (`getApplicationSupportDirectory()`) is used, which needs the Flutter
/// binding: call `WidgetsFlutterBinding.ensureInitialized()` first when you
/// open a storage before `runApp`.
///
/// In debug builds the storages opened here are shown in Flutter DevTools,
/// in the just_storage tab (see [debugDevToolsWorkbench]).
abstract final class JustStorage {
  static final Map<String, FileStorage> _standard = {};
  static final Map<String, EncryptedFileStorage> _encrypted = {};

  /// The [FileStorage] for [directory] (default: the app's support
  /// directory): plain JSON in `just_storage.json`.
  ///
  /// Pass a folder of your own in tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final storage = await JustStorage.standard(dir);
  /// ```
  static Future<JustStandardStorage> standard([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _standard.putIfAbsent(
      _idOf(dir),
      () => _shown(FileStorage(dir), directory, secure: false),
    );
  }

  /// The [EncryptedFileStorage] for [directory] (default: the app's support
  /// directory): AES-256-GCM in `just_secure_storage.enc`, with its key in
  /// `.storage.key`.
  ///
  /// Pass a folder of your own in tests:
  /// ```dart
  /// final dir = Directory.systemTemp.createTempSync('test_');
  /// final secure = await JustStorage.encrypted(dir);
  /// ```
  static Future<JustSecureStorage> encrypted([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return _encrypted.putIfAbsent(
      _idOf(dir),
      () => _shown(EncryptedFileStorage(dir), directory, secure: true),
    );
  }

  /// Whether debug builds show the app's storages in Flutter DevTools: the
  /// workbench of `package:just_storage/ui.dart`, in DevTools' just_storage
  /// tab, on the storages [standard] and [encrypted] open and those given
  /// to [debugShowInDevTools]. True by default.
  ///
  /// When the first storage opens, the app registers a service extension
  /// and says in the console how to open the tab. Set this to false before
  /// that to keep both away. Release and profile builds never do either,
  /// and the app does no work for the tab while it isn't open.
  static bool get debugDevToolsWorkbench => WorkbenchService.enabled;
  static set debugDevToolsWorkbench(bool value) =>
      WorkbenchService.enabled = value;

  /// Shows [storage] as [name] in Flutter DevTools' just_storage tab, in
  /// debug builds: one [standard] and [encrypted] didn't make, such as a
  /// storage of your own over them. Theirs are shown already.
  ///
  /// A storage of the same [name] is replaced; [storage], when shown
  /// already, is renamed. Does nothing in release and profile builds, or
  /// when [debugDevToolsWorkbench] is false.
  static void debugShowInDevTools(
    String name,
    JustKeyValueStorage storage, {
    String? description,
  }) {
    assert(() {
      WorkbenchService.show(
        name,
        storage,
        description: description,
        platform: _admin,
      );
      return true;
    }());
  }

  static const StoragePlatformAdmin _admin = (
    describe: admin.describeStorage,
    canWipe: admin.canWipe,
    wipe: admin.wipeStorage,
  );

  /// Shows [storage], just opened, in DevTools (debug builds): "Standard"
  /// or "Secure" for the app's support directory, else named after
  /// [directory].
  static T _shown<T extends JustKeyValueStorage>(
    T storage,
    Directory? directory, {
    required bool secure,
  }) {
    assert(() {
      final kind = secure ? 'Secure' : 'Standard';
      final call = secure ? 'JustStorage.encrypted' : 'JustStorage.standard';
      final what = secure ? 'AES-256-GCM' : 'plain values';
      WorkbenchService.track(
        storage,
        name: directory == null ? kind : '$kind (${_folderName(directory)})',
        description: directory == null
            ? '$call(): $what'
            : '$call(${directory.path}): $what',
        platform: _admin,
      );
      return true;
    }());
    return storage;
  }

  /// The last part of [dir]'s path.
  static String _folderName(Directory dir) {
    final parts = dir.absolute.uri.pathSegments.where((s) => s.isNotEmpty);
    return parts.isEmpty ? dir.path : parts.last;
  }

  /// One name for every spelling of [dir]: relative, with `..` or a
  /// trailing separator, or (on Windows, whose file names ignore case) in
  /// another case.
  static String _idOf(Directory dir) {
    var path = dir.absolute.uri.normalizePath().toFilePath();
    final separator = Platform.pathSeparator;
    while (path.length > 1 && path.endsWith(separator)) {
      path = path.substring(0, path.length - 1);
    }
    return Platform.isWindows ? path.toLowerCase() : path;
  }
}
