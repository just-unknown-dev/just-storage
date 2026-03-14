/// UI components for just_storage admin interface.
///
/// Provides a complete Flutter UI for inspecting and managing stored data:
/// - Standard (plain key-value) storage viewer with search, add, edit, delete
/// - Secure (AES-256-GCM encrypted) storage viewer with the same operations
/// - Info tab with statistics, backend details, and danger-zone clear actions
///
/// ## Quick start
///
/// ```dart
/// import 'package:just_storage/ui.dart';
///
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => const JUStorageAdminScreen(),
/// ));
/// ```
///
/// Pass existing storage instances to inspect specific directories / localStorage
/// namespaces (useful when your app already wires up its own instances):
///
/// ```dart
/// JUStorageAdminScreen(
///   standard: myStandard,
///   secure: mySecure,
/// )
/// ```
library;

export 'src/ui/storage_provider.dart';
export 'src/ui/ju_storage_admin_screen.dart';
