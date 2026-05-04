# Just Storage

A Flutter package providing **standard** and **secure** key-value storage with typed JSON helpers and reactive watch streams — via `JustStandardStorage` and `JustSecureStorage`.

Built from scratch with no third-party storage wrappers (`shared_preferences`, `flutter_secure_storage`, etc.). On native platforms (Android, iOS, macOS, Linux, Windows) storage is backed by `dart:io` files; on web it uses the browser's `localStorage` — the same `JustStorage` factory selects the right backend automatically.

[![pub package](https://img.shields.io/pub/v/just_storage.svg)](https://pub.dev/packages/just_storage)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Contributing](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

> Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before opening an issue or pull request.

---

## Features

| | `JustStandardStorage` | `JustSecureStorage` |
|---|---|---|
| **Use case** | Non-sensitive app data (settings, preferences, game state) | Sensitive data (auth tokens, credentials, PII) |
| **Native backend** | Atomic JSON file via `dart:io` | AES-256-GCM encrypted JSON file |
| **Web backend** | `window.localStorage` (prefixed keys) | `window.localStorage` with AES-256-GCM |
| **Encryption** | None | AES-256-GCM with per-value random nonces |
| **Integrity check** | No | Yes — GCM auth tag rejects any tampered byte |
| **Persistence** | ✅ | ✅ |
| **Typed JSON helpers** | ✅ | ✅ |
| **Reactive `watch()` stream** | ✅ | ✅ |
| **Atomic writes** | ✅ native (rename-swap) / ✅ web (sync) | ✅ native (rename-swap) / ✅ web (sync) |
| **Admin UI** | ✅ via `package:just_storage/ui.dart` | ✅ via `package:just_storage/ui.dart` |

---

### When to choose just_storage

- You want **both** standard and secure storage under a single, uniform API.
- You need **WASM / Flutter Web** support for encrypted storage.
- You want **authenticated encryption** (AES-256-GCM) that detects file tampering — not just confidentiality.
- You want a **built-in admin UI** to inspect storage during development without extra tooling.
- You prefer **zero code generation** — no adapters, no `build_runner`.
- You want **reactive streams** on individual keys without pulling in a full reactive state library.

### When to choose something else

- You only need simple non-sensitive persistence and already use `shared_preferences` throughout your codebase — no reason to migrate.
- You rely on **OS-level secure enclave / Keychain / Keystore** hardware backing — use `flutter_secure_storage`.
- You store **large datasets** with complex queries — use a database (just_database, Isar, Drift, sqflite) rather than a key-value store.
- You need **Hive's binary TypeAdapter** format for performance-critical large objects.

## Comparison with similar packages

| | **just_storage** | `shared_preferences` | `flutter_secure_storage` | `hive` |
|---|---|---|---|---|
| **Non-sensitive storage** | ✅ `JustStandardStorage` | ✅ | ❌ | ✅ |
| **Encrypted storage** | ✅ `JustSecureStorage` | ❌ | ✅ | ✅ (encrypted box) |
| **Encryption algorithm** | AES-256-GCM | — | OS keychain / keystore | AES-256-CBC |
| **Authenticated encryption** (tamper detection) | ✅ GCM auth tag | — | Platform-dependent | ❌ |
| **Web support** | ✅ WASM-compatible | ✅ | ⚠️ unofficial / limited | ✅ |
| **Reactive `watch()` stream** | ✅ | ❌ | ❌ | ✅ (Box.watch) |
| **Typed JSON helpers** | ✅ built-in | ❌ | ❌ | ✅ via TypeAdapters |
| **Code generation required** | ❌ | ❌ | ❌ | ⚠️ for typed boxes |
| **Atomic writes** | ✅ rename-swap | ✅ platform-native | ✅ platform-native | ✅ |
| **Built-in admin UI** | ✅ `JUStorageAdminScreen` | ❌ | ❌ | ❌ |
| **Third-party storage wrappers** | ❌ none | SQLite / NSUserDefaults / SharedPreferences | OS keychain / keystore | Custom binary format |
| **Dependencies** | `path_provider`, `pointycastle`, `web` | `shared_preferences` platform plugins | `flutter_secure_storage` platform plugins | `hive`, `path_provider` |

---

## Getting started

Add the package to your app's `pubspec.yaml`:

```yaml
dependencies:
  just_storage: ^1.2.1
```

Use [JustStorage] to obtain instances — no `path_provider` import required in your app:

```dart
import 'package:just_storage/just_storage.dart';

// Standard storage
final JustStandardStorage storage = await JustStorage.standard();

// Secure storage
final JustSecureStorage secure = await JustStorage.encrypted();
```

Register both stores in your DI container (e.g. `just_di`):

```dart
import 'package:just_di/just_di.dart';

final standard = await JustStorage.standard();
final secure   = await JustStorage.encrypted();

JustDi.registerLazySingleton<JustStandardStorage>(() => standard);
JustDi.registerLazySingleton<JustSecureStorage>(() => secure);
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

## Admin UI

`just_storage` ships a built-in Flutter admin screen for inspecting and editing storage at runtime.  Import it from the separate `ui.dart` library to keep the UI dependencies optional:

```dart
import 'package:just_storage/ui.dart';

// Push the screen (creates its own storage instances automatically)
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => const JUStorageAdminScreen(),
));
```

Pass your own instances to inspect a specific directory or `localStorage` namespace:

```dart
JUStorageAdminScreen(
  standard: myStandardStorage,
  secure:   mySecureStorage,
)
```

Optionally supply a custom theme:

```dart
JUStorageAdminScreen(
  theme: ThemeData(colorSchemeSeed: Colors.teal),
)
```

The screen contains three tabs:

| Tab | Description |
|-----|-------------|
| **Standard** | Browse, search, add, edit, and delete plain key-value entries |
| **Secure** | Same operations for AES-256-GCM encrypted entries |
| **Info** | Entry counts, backend details, and danger-zone clear actions |

---

## Security model

### Native platforms (Android, iOS, macOS, Linux, Windows)

#### Encryption

`EncryptedFileStorage` uses **AES-256-GCM** (authenticated encryption) via the `pointycastle` package:

- **Algorithm**: AES-256-GCM
- **Key length**: 256 bits (32 bytes), generated once with `Random.secure()`
- **Nonce**: 96 bits (12 bytes), freshly generated per `write` call — nonce reuse is impossible
- **Auth tag**: 128 bits appended to every ciphertext — any modification to the file throws `StorageException` before any plaintext is returned
- **Each value independently encrypted**: compromising one entry's nonce does not affect others

#### Master key

The master key is stored in `<appSupportDir>/.storage.key`:

- Generated once with `Random.secure()` and flushed with `File.writeAsBytes(flush: true)`
- File permissions set to `0600` (owner-read-only) on POSIX platforms (Android, iOS, Linux, macOS)
- Protected by the OS app sandbox — inaccessible to other apps on Android (API 29+) and iOS without root

#### On-disk format

```json
{
  "access_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext+GCMtag>" },
  "refresh_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext+GCMtag>" }
}
```

#### Atomic writes

Both implementations write to a `.tmp` file first, then call `File.rename()` — an atomic OS-level swap on all supported platforms. A crash mid-write never corrupts the existing store.

### Web platform

`WebSecureStorage` uses the same **AES-256-GCM** algorithm via `pointycastle`. The master key is generated on first use with `Random.secure()` and stored in `localStorage` under a reserved key.

> **Note**: `localStorage` is accessible to all scripts running on the same origin. The security guarantee is equivalent to in-memory protection rather than OS-level sandboxing. Prefer a server-side solution for highly sensitive data in web applications.

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

