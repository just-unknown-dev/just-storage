import '../core/core.dart';
import '../core/workbench_service.dart';
import 'admin_support.dart' as admin;
import 'web_secure_storage.dart';
import 'web_storage.dart';

/// Opens the storages, on the web.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// ```
///
/// Every call hands back the **same** instance: a second [WebSecureStorage]
/// would keep its own copy of the values and miss this one's writes.
/// Because the instance is shared, disposing it affects everyone using it.
///
/// In debug builds the storages opened here are shown in Flutter DevTools,
/// in the just_storage tab (see [debugDevToolsWorkbench]).
abstract final class JustStorage {
  static WebStorage? _standard;
  static WebSecureStorage? _encrypted;

  /// The page's [WebStorage]: `localStorage`, keys prefixed `just_storage:`.
  ///
  /// [directory] is there so calls compile on every platform; the web has
  /// no folders, and it is ignored.
  static Future<JustStandardStorage> standard([Object? directory]) async =>
      _standard ??= _shown(
        WebStorage(),
        'Standard',
        'JustStorage.standard(): plain values',
      );

  /// The page's [WebSecureStorage]: AES-256-GCM values in `localStorage`,
  /// keys prefixed `just_secure:`, the key in IndexedDB.
  ///
  /// [directory] is there so calls compile on every platform; the web has
  /// no folders, and it is ignored.
  static Future<JustSecureStorage> encrypted([Object? directory]) async =>
      _encrypted ??= _shown(
        WebSecureStorage(),
        'Secure',
        'JustStorage.encrypted(): AES-256-GCM',
      );

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

  /// Shows [storage], just opened, in DevTools as [name] (debug builds).
  static T _shown<T extends JustKeyValueStorage>(
    T storage,
    String name,
    String description,
  ) {
    assert(() {
      WorkbenchService.track(
        storage,
        name: name,
        description: description,
        platform: _admin,
      );
      return true;
    }());
    return storage;
  }
}
