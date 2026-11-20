# Just Storage

**Standard** and **secure** key-value storage for Flutter, on every platform, with typed JSON helpers, a stream of each key's values, and an admin screen — through `JustStandardStorage` and `JustSecureStorage`.

No storage wrappers (`shared_preferences`, `flutter_secure_storage`, …): on Android, iOS, macOS, Linux and Windows the values are files written with `dart:io`; on the web they are in `localStorage`, encrypted with the browser's Web Crypto. One factory, `JustStorage`, picks the right one.

[![pub package](https://img.shields.io/pub/v/just_storage.svg)](https://pub.dev/packages/just_storage)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Contributing](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

> Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before opening an issue or pull request.

---

## Features

| | `JustStandardStorage` | `JustSecureStorage` |
|---|---|---|
| **For** | Values that need no secrecy: settings, preferences, game state | Tokens, credentials, personal data |
| **Native** | One JSON file | One file, every value AES-256-GCM encrypted |
| **Web** | `localStorage`, prefixed keys | `localStorage`, AES-256-GCM by Web Crypto, the key in IndexedDB |
| **Integrity check** | — | Yes: a changed value, or a value moved to another key, is detected |
| **Crash-safe saves** | ✅ native: temporary file renamed over the old one | ✅ native: the same |
| **Typed JSON helpers** | ✅ | ✅ |
| **`watch()` stream per key** | ✅ broadcast | ✅ broadcast |
| **`changes` stream of the whole storage** | ✅ broadcast | ✅ broadcast |
| **Changes from other tabs (web)** | ✅ | ✅ |
| **Admin screen** | ✅ `package:just_storage/ui.dart`, desktop and phone | ✅ values hidden until shown |

### When to choose just_storage

- You want **both** standard and secure storage behind one API.
- You need encrypted storage on **Flutter web** too, JS or WebAssembly.
- You want **authenticated encryption** (AES-256-GCM) that detects tampering, not only secrecy.
- You want an **admin screen** to look at storage during development.
- You prefer **no code generation**: no adapters, no `build_runner`.
- You want a **stream per key** without a full state library.

### When to choose something else

- You only keep a few non-sensitive values and already use `shared_preferences`: there is no reason to move.
- Your secrets must be guarded by the **OS keychain / keystore** or secure hardware: use `flutter_secure_storage`. just_storage keeps its key in a file beside the values (see [Security model](#security-model)).
- You store **large datasets** or query them: use a database (just_database, Drift, sqflite, Isar).
- You need **Hive's binary adapters** for large objects.

## Comparison with similar packages

| | **just_storage** | `shared_preferences` | `flutter_secure_storage` | `hive` |
|---|---|---|---|---|
| **Non-sensitive storage** | ✅ `JustStandardStorage` | ✅ | ❌ | ✅ |
| **Encrypted storage** | ✅ `JustSecureStorage` | ❌ | ✅ | ✅ (encrypted box) |
| **Encryption** | AES-256-GCM | — | OS keychain / keystore | AES-256-CBC |
| **Tamper detection** | ✅ GCM tag, bound to the key | — | Platform-dependent | ❌ |
| **Key kept in** | A file / IndexedDB, beside the values | — | OS keychain / keystore | Your code |
| **Web** | ✅ JS and WebAssembly | ✅ | ⚠️ limited | ✅ |
| **Stream per key** | ✅ | ❌ | ❌ | ✅ (`Box.watch`) |
| **Typed JSON helpers** | ✅ | ❌ | ❌ | ✅ via TypeAdapters |
| **Code generation** | ❌ | ❌ | ❌ | ⚠️ for typed boxes |
| **Admin screen** | ✅ `JustStorageAdminScreen` | ❌ | ❌ | ❌ |
| **Dependencies** | `path_provider`, `pointycastle`, `web` | platform plugins | platform plugins | `hive`, `path_provider` |

---

## Getting started

```yaml
dependencies:
  just_storage: ^2.0.0
```

Get the storages from `JustStorage`; no `path_provider` import needed:

```dart
import 'package:just_storage/just_storage.dart';

final JustStandardStorage storage = await JustStorage.standard();
final JustSecureStorage secure = await JustStorage.encrypted();
```

Each call hands back **one shared instance per folder** (per page on the web): a storage keeps its whole file in memory and writes it back whole, so two instances over one folder would write over each other's keys. Constructing `FileStorage` or `EncryptedFileStorage` yourself skips this; do it only where nothing else opens that folder, as in a test.

Called before `runApp`, the factory needs the Flutter binding for the app's support directory:

```dart
WidgetsFlutterBinding.ensureInitialized();
final storage = await JustStorage.standard();
```

Register the stores in your DI container (e.g. `just_di`):

```dart
import 'package:just_di/just_di.dart';

final standard = await JustStorage.standard();
final secure = await JustStorage.encrypted();

JustDi.registerLazySingleton<JustStandardStorage>(() => standard);
JustDi.registerLazySingleton<JustSecureStorage>(() => secure);
```

---

## Usage

Both types share one API, `JustKeyValueStorage`; they differ only in what happens where the values are kept.

```dart
final JustStandardStorage storage = await JustStorage.standard();

await storage.write('theme', 'dark');
final theme = await storage.read('theme'); // 'dark'

// Typed JSON
await storage.writeJson('profile', profile, (p) => p.toJson());
final profile = await storage.readJson('profile', Profile.fromJson);

// The current value, then every change; listen as often as you like.
storage.watch('theme').listen((value) => print('theme: $value'));

// Every change to the whole storage: writes, deletes and clears.
storage.changes.listen((change) {
  print(change.isClear ? 'all removed' : '${change.key}: ${change.value}');
});

final all = await storage.readAll();
await storage.delete('theme');
await storage.clear();
```

```dart
final JustSecureStorage secure = await JustStorage.encrypted();

await secure.write('access_token', token);
final token = await secure.read('access_token');

secure.watch('access_token').listen((value) {
  if (value == null) print('signed out');
});
```

A write's future completes once the value is saved: a fresh storage over the same place reads it back. Writes made close together share one save. When a save fails, the write throws a `StorageException` and the storage goes back to what is saved.

---

## Errors and recovery

Every operation throws a `StorageException` when it fails:

```dart
try {
  await secure.write('token', token);
} on StorageException catch (e) {
  print(e.message); // what went wrong
  print(e.cause); // the underlying error, if any
}
```

When what a storage keeps can't be read back — a file that isn't the JSON it writes, an encrypted value that fails its integrity check, a key file that is missing or damaged — every call throws a **`StorageCorruptException`**, and the storage **leaves what it found untouched**: nothing is overwritten by accident. `clear()` is how to start over; it works on a storage that can't be read:

```dart
try {
  token = await secure.read('access_token');
} on StorageCorruptException catch (e) {
  print('${e.source}: ${e.message} ${e.keys}');
  await secure.clear(); // the user signs in again
}
```

---

## Admin screen

`package:just_storage/ui.dart` has a workbench for looking at and editing storage while the app runs:

```dart
import 'package:just_storage/ui.dart';

Navigator.of(context).push(MaterialPageRoute<void>(
  builder: (_) => const JustStorageAdminScreen(),
));
```

It shows `JustStorage.standard()` and `JustStorage.encrypted()` unless you pass the storages to show, your own among them:

```dart
JustStorageAdminScreen(
  stores: [
    StorageAdminStore.standard(),
    StorageAdminStore.secure(),
    StorageAdminStore('Game saves', savesStorage, description: 'One per slot'),
  ],
  readOnly: true, // look, search, copy and export; change nothing
  theme: ThemeData(colorSchemeSeed: Colors.teal),
)
```

On a wide screen (840 px or more) a sidebar lists the storages beside the selected one's entries, with the selected value in a panel next to them; on a phone the same pieces are pages you drill into.

| | What it does |
|-----|-------------|
| **Entries** | Search keys (and values, when shown), sort by key, size or latest change, a type badge on each value. Check several to export or delete them at once; right-click (long-press on a phone) for more |
| **Values** | Text, formatted JSON or a JSON tree; edit in place with JSON checked as you type (Ctrl+S saves); rename, duplicate, copy, delete. A warning when the value changes while you edit it |
| **Live** | Follows each storage's `changes`: what the app writes shows up at once, marked for a moment |
| **Secure values** | Hidden until you show them; hidden values are not searched |
| **Export / import** | JSON you copy or save as a file (the Downloads folder, or a browser download), and import by pasting, picking a file or reading a path: merge, only new keys, or replace all |
| **Details** | Counts, sizes and value types; the file, folder, key file, or browser storage behind each storage; clear, and wipe (destroying the key) for secure storages |

Pass a `StorageAdminController` to share the screen's state or drive it from code. The screen can show and export secure values in plain text: keep it out of release builds, or behind your own developer switch, and use `readOnly: true` where it must not change anything.

---

## Security model

### What it protects against

- **Reading the values from a copy of the data alone**: a leaked `just_secure_storage.enc` (or a copied `localStorage`) without its key is AES-256-GCM ciphertext.
- **Changes to the values**: each value carries a 16-byte GCM tag and is bound to its key, so a changed value, or one moved to another key, makes the storage throw a `StorageCorruptException` rather than return it.

### What it does not protect against

- **Anyone who can read the app's folder**: the key lives beside the values (`.storage.key`). That includes the user, an administrator, malware running as the user, a rooted device, and **device backups** (Android Auto Backup and iCloud back up the app's support folder, key included). Use `flutter_secure_storage` when the key must sit in the OS keychain or keystore.
- **Code running in your web page**: it can use the key, as this package does. The key can't be read out, but values can be decrypted on the page.
- **Key names**: only values are encrypted. Don't put secrets in keys.

### Native platforms (Android, iOS, macOS, Linux, Windows)

- **Values**: `just_secure_storage.enc`, AES-256-GCM (pointycastle). Each value has its own random 12-byte nonce; its key is the additional authenticated data. Only values that changed are encrypted again when the file is saved.
- **Key**: `.storage.key`, 32 random bytes from `Random.secure()`, made on the first write. On Linux and macOS it is `0600`; on Windows its access list names only the user; on Android and iOS the app's folder is private to the app. A key is never made again while the file holds values sealed with the old one: a missing or damaged key makes the storage throw until `clear()`.
- **Saving**: each save writes a temporary file and renames it over the old one, so a crash leaves the old file or the new one, never half of one.

```json
{
  "v": 2,
  "entries": {
    "access_token": { "n": "<base64 nonce>", "ct": "<base64 ciphertext + GCM tag>" }
  }
}
```

### Web

- **Values**: one `localStorage` item each, `just_secure:<key>`, encrypted by Web Crypto (AES-256-GCM, a random nonce per value, the key as additional data): `{"v": 2, "n": …, "ct": …}`. Web Crypto needs a secure page (`https:` or `localhost`).
- **Key**: a **non-extractable** `CryptoKey` in IndexedDB (database `just_storage`): scripts on the page can use it but can't read its bytes. Where IndexedDB is unavailable the key is kept raw in `localStorage`.
- `localStorage` holds about 5 MB per origin; a write past that throws a `StorageException`.

---

## Testing

The native storages take a folder, so tests pass a temporary one:

```dart
final dir = Directory.systemTemp.createTempSync('test_');
addTearDown(() => dir.deleteSync(recursive: true));
final storage = FileStorage(dir); // or EncryptedFileStorage(dir)
```

`await storage.dispose()` waits for the saves under way and ends the `watch` streams; the storage still works afterwards.

---

## Upgrading from 1.x

- Files written by 1.x are read as they are, and the encrypted ones are written again in format 2 straight away; the web's raw `localStorage` key moves to IndexedDB. A 1.x app can't read format 2 back.
- `JUStorageAdminScreen` → `JustStorageAdminScreen`; `StorageProvider` → `StorageAdminController`.
- A file that can't be read now throws `StorageCorruptException` instead of starting empty and being overwritten on the next write. Catch it and call `clear()` to start over.
- `watch()` returns a broadcast stream: listen as often as you like.
- `FileStorage.dispose()` and `WebStorage.dispose()` return a `Future`; `EncryptedFileStorage.dispose(destroyKey: true)` is `wipe()`.

See the [CHANGELOG](CHANGELOG.md) for everything.
