/// An admin screen for just_storage: look at, search, add, edit and delete
/// the values of a standard and a secure storage while the app runs.
///
/// ```dart
/// import 'package:just_storage/ui.dart';
///
/// Navigator.of(context).push(MaterialPageRoute<void>(
///   builder: (_) => const JustStorageAdminScreen(),
/// ));
/// ```
///
/// It shows secure values in plain text when asked to: keep it out of
/// release builds, or behind your own developer switch.
library;

export 'src/ui/ui.dart';
