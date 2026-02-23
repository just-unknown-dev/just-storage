/// Recipe: Wiring just_storage into a GetIt dependency-injection container.
///
/// Copy this pattern into your app's `injection_container.dart`.  Both
/// storage instances are registered as lazy singletons — they are constructed
/// once on first use and reused for the lifetime of the app.
///
/// This file is documentation-only and is not intended to be run directly.
library;

// ignore_for_file: unused_import

// ---------------------------------------------------------------------------
// Example injection_container.dart excerpt
// ---------------------------------------------------------------------------
//
// import 'dart:io';
// import 'package:get_it/get_it.dart';
// import 'package:just_storage/just_storage.dart';
// import 'package:path_provider/path_provider.dart';
//
// final sl = GetIt.instance;
//
// Future<void> init() async {
//   // ─── Storage layer ────────────────────────────────────────────────────
//   //
//   // Resolve the app-private support directory once during app startup.
//   // Both stores share the same directory; they write to different files:
//   //   just_storage.json         ← FileStorage
//   //   just_secure_storage.enc   ← EncryptedFileStorage
//   //   .storage.key              ← AES-256 master key (managed internally)
//
//   final storageDir = await getApplicationSupportDirectory();
//
//   final standard = await JustStorage.standard();
//   final secure   = await JustStorage.encrypted();
//
//   sl.registerLazySingleton<JustStandardStorage>(() => standard);
//   sl.registerLazySingleton<JustSecureStorage>(() => secure);
//
//   // ─── Services that depend on storage ─────────────────────
//
//   sl.registerLazySingleton(
//     () => SettingsService(sl<JustStandardStorage>()),
//   );
//
//   sl.registerLazySingleton(
//     () => AuthTokenService(sl<JustSecureStorage>()),
//   );
// }

// ---------------------------------------------------------------------------
// Notes
// ---------------------------------------------------------------------------
//
// • Never inject FileStorage or EncryptedFileStorage directly into callers.
//   Always inject JustStandardStorage / JustSecureStorage so callers remain
//   testable and decoupled from the storage implementation.
//
// • In tests, substitute a temp-directory-backed instance directly:
//
//     final dir = await Directory.systemTemp.createTemp('test_');
//     final storage = FileStorage(dir);
//     // — or —
//     final secure = EncryptedFileStorage(dir);
//
// • If you need separate namespaces (e.g. player A vs player B data), just
//   pass different subdirectories:
//
//     final playerDir = Directory('${baseDir.path}/player_${userId}');
//     final playerStorage = FileStorage(playerDir);
