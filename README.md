# Just Storage

A Flutter package providing **standard** and **secure** key-value storage with typed JSON helpers and reactive watch streams — via `JustStandardStorage` and `JustSecureStorage`.

Both implementations are built from scratch using only `dart:io`, `path_provider` (for directory resolution), and `pointycastle` (AES-256-GCM encryption). No third-party storage wrappers (`shared_preferences`, `flutter_secure_storage`, etc.) are used.

[![pub package](https://img.shields.io/pub/v/just_storage.svg)](https://pub.dev/packages/just_storage)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Contributing](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

> Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before opening an issue or pull request.

---

## Features

| | `JustStandardStorage` | `JustSecureStorage` |
|---|---|---|
| **Use case** | Non-sensitive app data (settings, preferences, game state) | Sensitive data (auth tokens, credentials, PII) |
| **Storage** | Atomic JSON file via `dart:io` | AES-256-GCM encrypted JSON file |
| **Encryption** | None | AES-256-GCM with per-value random nonces |
| **Integrity check** | No | Yes — GCM auth tag rejects any tampered byte |
| **Persistence** | ✅ | ✅ |
| **Typed JSON helpers** | ✅ | ✅ |
| **Reactive `watch()` stream** | ✅ | ✅ |
| **Atomic writes** | ✅ (rename-swap) | ✅ (rename-swap) |

---

## Getting started

Add the package to your app's `pubspec.yaml`:

```yaml
dependencies:
  just_storage: ^1.0.0
```

Use [JustStorage] to obtain instances — no `path_provider` import required in your app:

```dart
import 'package:just_storage/just_storage.dart';

// Standard storage
final JustStandardStorage storage = await JustStorage.standard();

// Secure storage
final JustSecureStorage secure = await JustStorage.encrypted();
```

Register both stores in your DI container (e.g. `get_it`):

```dart
final standard = await JustStorage.standard();
final secure   = await JustStorage.encrypted();

sl.registerLazySingleton<JustStandardStorage>(() => standard);
sl.registerLazySingleton<JustSecureStorage>(() => secure);
```

---

## Usage

### Standard storage (`JustStandardStorage`)

```dart
final JustStandardStorage storage = await JustStorage.standard();

// Read / write
await storage.write('theme', 'dark');
final theme = await storage.read('theme'); // 'dark'

// Typed JSON
await storage.writeJson('profile', profile, (p) => p.toJson());
final profile = await storage.readJson('profile', Profile.fromJson);

// Reactive watch — emits current value then every subsequent change
storage.watch('theme').listen((value) {
  print('theme changed to: $value');
});

// Read all
final all = await storage.readAll();

// Delete / clear
await storage.delete('theme');
await storage.clear();
```

### Secure storage (`JustSecureStorage`)

```dart
final JustSecureStorage secure = await JustStorage.encrypted();

// Read / write (values are AES-256-GCM encrypted on disk)
await secure.write('access_token', token);
final token = await secure.read('access_token');

// Typed JSON
await secure.writeJson('user_credentials', creds, (c) => c.toJson());
final creds = await secure.readJson('user_credentials', Credentials.fromJson);

// Bulk operations
final all = await secure.readAll();
await secure.clear();

// Watch
secure.watch('access_token').listen((value) {
  if (value == null) print('logged out');
});
```

Both types share the **same method surface** — the only difference is what happens on disk (plain JSON vs. encrypted JSON).

---

## Security model

### Encryption

`EncryptedFileStorage` uses **AES-256-GCM** (authenticated encryption) via the `pointycastle` package:

- **Algorithm**: AES-256-GCM
- **Key length**: 256 bits (32 bytes), generated once with `Random.secure()`
- **Nonce**: 96 bits (12 bytes), freshly generated per `write` call — nonce reuse is impossible
- **Auth tag**: 128 bits appended to every ciphertext — any modification to the file throws `StorageException` before any plaintext is returned
- **Each value independently encrypted**: compromising one entry's nonce does not affect others

### Master key

The master key is stored in `<appSupportDir>/.storage.key`:

- Generated once with `Random.secure()` and flushed with `File.writeAsBytes(flush: true)`
- File permissions set to `0600` (owner-read-only) on POSIX platforms (Android, iOS, Linux, macOS)
- Protected by the OS app sandbox — inaccessible to other apps on Android (API 29+) and iOS without root

### On-disk format

```json
{
  "access_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext+GCMtag>" },
  "refresh_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext+GCMtag>" }
}
```

### Atomic writes

Both implementations write to a `.tmp` file first, then call `File.rename()` — an atomic OS-level swap on all supported platforms. A crash mid-write never corrupts the existing store.

---

## Error handling

All operations throw `StorageException` on failure:

```dart
try {
  await secure.read('token');
} on StorageException catch (e) {
  print(e.message);  // human-readable description
  print(e.cause);    // underlying exception, if any
}
```

A `StorageException` is also thrown if:
- the encrypted file was modified externally (GCM tag mismatch)
- the master key file is corrupt (wrong byte count)

---

## Testing

Both implementations accept a `Directory` via constructor, so tests simply pass `Directory.systemTemp.createTempSync()`:

```dart
final dir = Directory.systemTemp.createTempSync('test_');
final storage = FileStorage(dir);        // or EncryptedFileStorage(dir)
addTearDown(() => dir.deleteSync(recursive: true));
```

