/// Recipe: Testing services that use just_storage.
///
/// Because both [FileStorage] and [EncryptedFileStorage] accept a [Directory]
/// via their constructor, tests need no mocks, no platform channels, and no
/// special test setup.  Simply create a temp directory, pass it to the
/// concrete class, and tear it down.
library;

// ---------------------------------------------------------------------------
// Example test file
// ---------------------------------------------------------------------------
//
// import 'dart:io';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:just_storage/just_storage.dart';
// import 'package:your_app/settings_service.dart';
// import 'package:your_app/auth_token_service.dart';
//
// void main() {
//   late Directory tempDir;
//   late JustStandardStorage storage;
//   late JustSecureStorage secure;
//
//   setUp(() async {
//     tempDir = await Directory.systemTemp.createTemp('test_');
//     storage = FileStorage(tempDir);
//     secure  = EncryptedFileStorage(tempDir);
//   });
//
//   tearDown(() => tempDir.delete(recursive: true));
//
//   // ─── SettingsService ─────────────────────────────────────────────────
//
//   group('SettingsService', () {
//     late SettingsService service;
//     setUp(() => service = SettingsService(storage));
//
//     test('returns defaults when nothing stored', () async {
//       final s = await service.load();
//       expect(s.theme, ChessTheme.system);
//       expect(s.soundEnabled, isTrue);
//     });
//
//     test('save then load round-trips', () async {
//       await service.save(
//         const AppSettings(
//           theme: ChessTheme.dark,
//           boardStyle: BoardStyle.walnut,
//           soundEnabled: false,
//         ),
//       );
//       final loaded = await service.load();
//       expect(loaded.theme, ChessTheme.dark);
//       expect(loaded.soundEnabled, isFalse);
//     });
//
//     test('update only changes the requested field', () async {
//       await service.update((s) => s.copyWith(soundEnabled: false));
//       final s = await service.load();
//       // Default theme still in place:
//       expect(s.theme, ChessTheme.system);
//       // Sound toggled:
//       expect(s.soundEnabled, isFalse);
//     });
//
//     test('watch emits update reactively', () async {
//       final events = <AppSettings>[];
//       final sub = service.watchSettings().listen(events.add);
//       await service.save(const AppSettings(theme: ChessTheme.light));
//       await sub.cancel();
//       expect(events.last.theme, ChessTheme.light);
//     });
//   });
//
//   // ─── AuthTokenService ─────────────────────────────────────────────────
//
//   group('AuthTokenService', () {
//     late AuthTokenService service;
//     setUp(() => service = AuthTokenService(secure));
//
//     test('unauthenticated initially', () async {
//       expect(await service.isAuthenticated(), isFalse);
//     });
//
//     test('isAuthenticated after saving non-expired tokens', () async {
//       await service.saveTokens(OAuthTokens(
//         accessToken:  'access.abc',
//         refreshToken: 'refresh.xyz',
//         expiresAt:    DateTime.now().add(const Duration(hours: 1)),
//         username:     'Magnus',
//       ));
//       expect(await service.isAuthenticated(), isTrue);
//     });
//
//     test('logout clears tokens', () async {
//       await service.saveTokens(OAuthTokens(
//         accessToken:  'access.abc',
//         refreshToken: 'refresh.xyz',
//         expiresAt:    DateTime.now().add(const Duration(hours: 1)),
//         username:     'Magnus',
//       ));
//       await service.logout();
//       expect(await service.isAuthenticated(), isFalse);
//     });
//
//     test('tokens survive reopening the secure store', () async {
//       await service.saveTokens(OAuthTokens(
//         accessToken:  'access.tok',
//         refreshToken: 'refresh.tok',
//         expiresAt:    DateTime.now().add(const Duration(hours: 1)),
//         username:     'Hikaru',
//       ));
//
//       // Re-open from the same directory — real decrypt from disk.
//       final service2 = AuthTokenService(EncryptedFileStorage(tempDir));
//       final loaded = await service2.loadTokens();
//       expect(loaded?.username, 'Hikaru');
//     });
//   });
// }
