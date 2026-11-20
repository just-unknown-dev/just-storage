/// Standard and secure key-value storage for Flutter, on every platform,
/// with typed JSON helpers, a stream of each key's values and a stream of
/// every change.
///
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
/// await storage.write('theme', 'dark');
/// storage.watch('theme').listen((v) => print('theme: $v'));
/// storage.changes.listen((change) => print(change));
///
/// final JustSecureStorage secure = await JustStorage.encrypted();
/// await secure.write('access_token', token);
/// ```
///
/// On Android, iOS, Linux, macOS and Windows the values are files in the
/// app's support directory ([FileStorage], [EncryptedFileStorage]); on the
/// web, `localStorage` ([WebStorage], [WebSecureStorage]). [JustStorage]
/// picks the right one. Secure values are encrypted with AES-256-GCM.
///
/// The admin screen for looking at and editing the values is in
/// `package:just_storage/ui.dart`.
library;

export 'src/core/core.dart';
export 'src/file/file.dart' if (dart.library.js_interop) 'src/web/web.dart';
