/// just_storage — a Flutter package providing standard and secure key-value
/// storage with typed JSON helpers and reactive watch streams.
///
/// Both implementations are built from scratch using only `dart:io`,
/// `path_provider` (for path resolution), and `pointycastle` (AES-256-GCM
/// encryption). No third-party storage packages are used.
///
/// ## Quick start
///
/// **Standard (non-sensitive) storage:**
/// ```dart
/// final JustStandardStorage storage = await JustStorage.standard();
///
/// await storage.write('theme', 'dark');
/// final theme = await storage.read('theme'); // 'dark'
///
/// storage.watch('theme').listen((v) => print('theme changed: $v'));
/// ```
///
/// **Secure (encrypted) storage — AES-256-GCM, per-value nonces:**
/// ```dart
/// final JustSecureStorage secure = await JustStorage.encrypted();
///
/// await secure.write('access_token', token);
/// final token = await secure.read('access_token');
/// ```
library;

// Factory
export 'src/just_storage_factory.dart';

// Interfaces
export 'src/just_standard_storage.dart';
export 'src/just_secure_storage.dart';

// Model
export 'src/models/storage_exception.dart';

// Implementations (exposed for direct use in tests)
export 'src/implementations/file_storage.dart';
export 'src/implementations/encrypted_file_storage.dart';
