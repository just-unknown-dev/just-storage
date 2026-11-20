/// The storage workbench of just_storage, for Flutter.
///
/// [JustStorageAdminScreen] shows the storages it is given — the app's
/// standard and secure ones by default — while the app runs: it searches,
/// adds, edits, renames, duplicates and deletes entries, shows values as
/// text, formatted JSON or a tree, exports and imports JSON, and shows where
/// each storage keeps its values. A sidebar and panels on wide screens,
/// pages on phones; it follows each storage's changes as they happen.
/// [StorageAdminController] holds its state, over a list of
/// [StorageAdminStore]s; `readOnly: true` makes a screen that changes
/// nothing.
///
/// ```dart
/// import 'package:just_storage/ui.dart';
///
/// Navigator.of(context).push(MaterialPageRoute<void>(
///   builder: (_) => const JustStorageAdminScreen(),
/// ));
/// ```
///
/// It shows and exports secure values in plain text when asked to: keep it
/// out of release builds, or behind your own developer switch.
library;

export 'src/ui/ui.dart';
