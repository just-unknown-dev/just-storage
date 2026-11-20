## [2.0.0] - Unreleased

An audit of the whole package: data that could be lost or overwritten without a word now isn't, the encrypted format binds each value to its key, the web key can no longer be read by scripts, and the code is laid out by feature. Every storage reports its changes as a stream, and the admin screen is rebuilt as a workbench for desktop and phones. Requires Dart ^3.11.0 and Flutter >=3.47.1.

### Breaking

- **A storage that can't be read throws `StorageCorruptException`** (new, a `StorageException`) instead of starting empty — which the next write then saved over the old file. This covers a file that isn't the JSON the storage writes (or holds values that aren't strings), an encrypted value that fails its check, and a missing or damaged key. What was found is left untouched; `clear()` starts over and works on a storage that can't be read. The exception names the file (`source`) and, when only some values fail, their `keys`.
- **The encrypted format is version 2**, on native platforms and on the web: each value is sealed with its key as additional authenticated data, so a value moved to another key fails its check. Native files are `{"v": 2, "entries": {...}}`; web items are `{"v": 2, "n": ..., "ct": ...}`. Version 1 is still read, and written again as version 2 straight away; 1.x can't read version 2.
- **The web key moves to IndexedDB** as a non-extractable `CryptoKey`, out of `localStorage` where any script could read its bytes. A 1.x key is moved, and its raw copy removed, the first time it is used. Where IndexedDB is unavailable the key stays raw in `localStorage`.
- **The admin screen is rebuilt: `JustStorageAdminScreen`** (was `JUStorageAdminScreen`) takes `stores:` — a list of `StorageAdminStore` (new) — in place of `standard:` and `secure:`, plus `controller:`, `readOnly:` and `title:`. Its state is `StorageAdminController` (was `StorageProvider`): `stores`, `entriesOf`, `errorOf`, `isLoaded`, `select`/`selectedStore`/`selectedKey`, `refresh`, `write`, `delete` (several keys), `rename`, `copy`, `clear`, `wipe`, `importEntries` and `exportJson`; its changes throw what the storage throws, and a `StateError` when read-only. `EntriesTab` and `InfoTab` are gone.
- **`JustKeyValueStorage.changes`** is a new member, so a class that `implements` `JustStandardStorage`, `JustSecureStorage` or `JustKeyValueStorage` must add it.
- **`watch()` returns a broadcast stream**, as its documentation always said: it can be listened to many times, each listener getting its own first value. It was a single-subscription stream. Streams end when the storage is disposed.
- **`dispose()` returns a `Future`** on `FileStorage` and `WebStorage` too, and waits for the writes, deletes and clears called so far. `EncryptedFileStorage.dispose(destroyKey: true)` is now `wipe()`, also on `WebSecureStorage`.
- **`readJson` throws a `StorageException`** for a value that isn't a JSON object, as it already did; the documentation said it returned `null`.
- `FileStorage(directory)` and `EncryptedFileStorage(directory)` keep their constructors; `StorageKeyManager`, `AesGcmCipher` and `WebAesGcmCipher` are internal now (they were never exported).
- Dart ^3.11.0 (was >=3.3.0), Flutter >=3.47.1 (was >=3.19.0), path_provider ^2.1.5, web ^1.1.1. pointycastle may be 3.x or 4.x (`>=3.7.3 <5.0.0`, was ^3.7.3): 4.x is the latest, and the `encrypt` package still needs 3.x.

### Added

- `JustKeyValueStorage`, what `JustStandardStorage` and `JustSecureStorage` share, with `readJson` and `writeJson` built on `read` and `write` for any implementation.
- `StorageCorruptException`, with `source` and `keys`.
- `EncryptedFileStorage.wipe()` and `WebSecureStorage.wipe()`: remove every value and delete the key, so a copy of the old data can't be decrypted.
- `FileStorage.file`, `FileStorage.directory`, `FileStorage.fileName`; `EncryptedFileStorage.file`, `.keyFile`, `.directory`, `.fileName`; `WebStorage.prefix`, `WebSecureStorage.prefix`.
- On the web, changes made in another tab of the page reach this tab's values and `watch` streams.
- **`changes`**, a broadcast stream of every change to a storage: a `StorageChange` (new: `key`, `value`, `isDelete`, `isClear`) for each key written or deleted, and `StorageChange.cleared()` when every key goes. Reported once saved — a failed write reports nothing — and, on the web, for other tabs' changes too. `StorageChange.toString()` never shows the value.
- **The admin screen is a workbench**, after just_database's:
  - **Layouts**: on a wide screen a resizable sidebar of storages, the selected one's entries, and the selected value in a side panel (or a dialog when there is no room); on a phone, pages: storages → entries → a value. A phone page gives way when the window gets wide.
  - **Storages**: the app's standard and secure ones by default, or any list of `StorageAdminStore`s — the engine's own store, say — each with a name and a description.
  - **Live**: it follows each storage's `changes`, so what the app writes shows up at once, marked for a moment.
  - **Entries**: search (keys only while secure values are hidden), sort by key, size or latest change, a theme-coloured type badge (text, number, boolean, JSON object or array, empty), sizes, check boxes for exporting or deleting several at once, a menu on each (right-click, or long-press to select on a phone).
  - **Values**: text, formatted JSON or a tree that opens and closes; edited in place with JSON checked as you type (line and column of an error), format and minify, Ctrl+S to save, Esc to cancel, and a warning when the value changes while you edit it; rename, duplicate, copy key or value, delete; a deleted value can be written back.
  - **Export and import**: JSON with the storage's name, to copy or save (a `just_storage` folder in Downloads, or a browser download); secure exports warn that values come out decrypted and preview them masked. Import pastes, picks a file (web), reads a path (desktop) or an earlier export; previews what is new and what exists; merges, adds only new keys, or replaces all.
  - **Details**: entries, sizes, largest value and value types; where the values are — folder, file, key file, or the browser origin, prefix and key — with paths to copy; what protects them; clear, and wipe (destroying the key) for secure storages, each confirmed by typing the storage's name.
  - **`readOnly: true`**: looking, searching, copying and exporting only.

### Changed

- **Writes made close together share one save** instead of rewriting the file once each; a write of the value the file already holds saves nothing.
- Only the encrypted values that changed are encrypted again when the file is saved, instead of every value on every write.
- The key file is written to a temporary file, narrowed to its owner, then renamed into place: it never exists half-written, or with wider permissions. Of two storages, or two processes, making the key at once, one makes it and the other uses it.
- The key file is owner-only on Windows too (its access list names only the user), and is no longer `chmod`ed on Android and iOS, whose app folders are private already (iOS can't start a process).
- The code is laid out by feature — `core/`, `file/`, `web/`, `ui/` — with a layout guard test, and every public name is documented (`public_member_api_docs`).

### Fixed

- **Lost keys with several handles** — `JustStorage.standard()` and `JustStorage.encrypted()` return one shared instance per folder instead of a new `FileStorage` / `EncryptedFileStorage` on every call. Each instance keeps the whole store and rewrites the file on every write, so two handles over the same folder dropped each other's keys. Different spellings of one folder (relative, `..`, a trailing separator, letter case on Windows) share an instance. On the web both factories return one instance too, so a second `WebSecureStorage` no longer serves stale values.
- **A failed save left the value in memory**: the write threw, but reads returned the unsaved value, and the next successful save wrote it. The keys a failed save held now go back to what the file holds, and watchers never hear of them.
- **A write and a delete of one key on the web could land out of order**, bringing a deleted value back after a reload: web secure writes are now saved one at a time, in order.
- **`dispose()` didn't wait** for the save under way, so a value written just before closing the app could be lost.
- **Encrypted values with malformed fields were dropped silently** on native (skipped on load, then left out of the next save), and on the web every undecryptable value was skipped. Both now throw `StorageCorruptException`, leaving the data alone.
- **A missing key file was replaced by a new key** while the file held values sealed with the old one, making them unreadable for good. No key is made while values need the old one.
- **A key file half-written by a crash** was taken for a damaged key and failed forever; an empty key file another process is still writing is now waited for.
- **Temporary files left by a crash** (`*.tmp.*`) piled up beside the store; ones older than a minute are swept when the store is opened. A failed save deletes its own.
- **Encrypted temporary file collision** — `EncryptedFileStorage`'s `.tmp` file gets a unique name, as `FileStorage`'s did in 1.2.1. Names now carry the process id too.
- **`FileStorage.watch` failed silently**: an error loading the file escaped as an uncaught error instead of reaching the listener.
- **A failure while loading was kept forever** (the failed load was cached); the next call now reads the file again, so a file put right is picked up.
- **Admin screen**: adding an entry under a key that held a value replaced that value without a word (it now says the key is taken); keys and values asked for the generic `monospace` font, which only Android and Linux have; switching tabs lost the search and the shown values; "Format as JSON" did nothing, silently, for text that wasn't JSON; "NaN" and "Infinity" were badged as numbers; it spun forever when a storage failed to load; it threw "used after being disposed" when closed while loading; it didn't let you save an empty value; the danger zone couldn't clear a storage that couldn't be read; and its info tab claimed that nonce reuse "never compromises other keys" and that the key file is `0600` on Android and iOS.
- **Docs**: the README said the web used pointycastle (it uses Web Crypto), that nonce reuse is impossible, and that a compromised nonce affects one entry only (a reused GCM nonce exposes the authentication key for every value). The security model now says what the encryption protects against and what it doesn't — in particular that the key sits beside the values, and backups include both.
- The examples are formatted (`example.dart`, `auth_service_example.dart`, `settings_service_example.dart`), so the CI's format check passes; the CI workflow runs on `release/**` branches (it watched `release-v*.*.*`, which no branch matched), on Flutter 3.47.9, and runs the web tests in Chrome.

---

## [1.2.1] - 2026-04-27

### Fixed

- **Temporary file collision** — `FileStorage._doFlush` now appends a microsecond-precision suffix to the `.tmp` filename (`<name>.<microseconds>`) so that concurrent flush operations can never overwrite each other's in-flight temporary file before the atomic rename completes.

---

## [1.2.0] - 2026-04-23

### Added

- `WebAesGcmCipher` — new web/WASM AES-256-GCM backend powered by the browser's native Web Crypto API (`window.crypto.subtle`) with typed import/encrypt/decrypt helpers and secure key/nonce generation via `getRandomValues`.

### Changed

- `WebSecureStorage` now uses `WebAesGcmCipher` instead of the pure-Dart cipher on web, with async one-time initialization (`_initFuture`) and imported `CryptoKey` usage for encrypt/decrypt operations.
- **README** — updated the package version snippet to `^1.2.0` and switched the dependency-injection setup example to `just_di` (`JustDi.registerLazySingleton`) instead of a `get_it`-style registration snippet.
- `pubspec.yaml` constraints were raised to `sdk: >=3.3.0 <4.0.0` and `flutter: >=3.19.0` for this release.

### Fixed

- **Write ordering / race safety** — `FileStorage` and `EncryptedFileStorage` now serialize flush operations through a chained future to prevent overlapping writes.
- **Reinitialization after dispose** — both native storage implementations now reset initialization/flush state in `dispose()` so instances can be safely re-used.
- **Encrypted cache loading robustness** — malformed encrypted entry fields are validated explicitly; malformed-format entries are skipped while AES-GCM authentication failures still propagate as `StorageException`.
- **AES-GCM input validation** — `AesGcmCipher` now throws `StorageException` for invalid key/nonce lengths (instead of assert-only checks).

---

## [1.1.2] - 2026-03-14

### Changed

- **README** — added a *Comparison with similar packages* section with a feature matrix table contrasting `just_storage` against `shared_preferences`, `flutter_secure_storage`, and `hive`, plus guidance on when to choose each package.

---

## [1.1.1] - 2026-03-14

### Fixed

- **WASM compatibility** — replaced `dart:html` imports in `WebStorage` and `WebSecureStorage` with `package:web` (`web: ^1.0.0`); changed all conditional export guards from `dart.library.html` to `dart.library.js_interop`, which is available on both JS web and WASM targets.  The package is now compatible with `dart compile wasm` and Flutter WASM builds.

- **Missing documentation warnings** — added doc comments to the previously undocumented constructors: `EncryptedFileStorage.new`, `FileStorage.new`, `JustSecureStorage.new`, `JustStandardStorage.new`, and `StorageException.new`.  Resolves the `missing_code_block_language_in_doc_comment` / pub.dev documentation score warnings.

### Changed

- **Example** (`example/example.dart`) — Example page added to demonstrate basic usage of `JustStorage` in a Flutter app, including reading/writing values, using the reactive `watch()` stream, and displaying the admin UI.

---

## [1.1.0] - 2026-03-14

### Added

- **Web platform support** — `JustStorage.standard()` and `JustStorage.encrypted()` now resolve to web-specific backends on Flutter Web via conditional imports; no API changes required in consuming code.

- `WebStorage` — `JustStandardStorage` implementation for web, backed by `window.localStorage`.
  - Values stored under keys prefixed with `just_storage:` to avoid collisions
  - Full `read`, `write`, `delete`, `clear`, `containsKey`, `readAll`, `readJson`, `writeJson`, and `watch()` support
  - `StreamController.broadcast(sync: true)` per key for zero-latency `watch()` delivery

- `WebSecureStorage` — `JustSecureStorage` implementation for web, backed by `window.localStorage` with AES-256-GCM authenticated encryption.
  - Master key generated on first use with `Random.secure()`, stored under a reserved `localStorage` key
  - Per-value random 12-byte nonce (fresh on every `write`) — same nonce-reuse prevention as `EncryptedFileStorage`
  - Data entries stored under keys prefixed with `just_secure:` in the format `{ "n": "<base64 nonce>", "ct": "<base64 ciphertext+GCMtag>" }`
  - In-memory cache populated on first access; corrupt entries are silently skipped on load
  - Full `read`, `write`, `delete`, `clear`, `containsKey`, `readAll`, `readJson`, `writeJson`, and `watch()` support

- `JustStorageFactory` — conditional export (`just_storage_factory_native.dart` / `just_storage_factory_web.dart`) so the correct `JustStorage` implementation is selected at compile time with no runtime platform checks.

- **Admin UI** (`package:just_storage/ui.dart`) — a complete Flutter admin screen for inspecting and editing storage at runtime.
  - `JUStorageAdminScreen` — full-screen widget with three tabs:
    - **Standard** — browse, search, add, edit, and delete plain key-value entries
    - **Secure** — same operations for AES-256-GCM encrypted entries
    - **Info** — entry counts, backend details, and danger-zone clear actions
  - Accepts optional `standard` and `secure` constructor parameters to inject existing storage instances (useful when the app already wires up its own)
  - Accepts an optional `theme` parameter to override the surrounding app theme
  - `StorageProvider` (`ChangeNotifier`) — internal state manager; creates its own storage instances via `JustStorage` when none are supplied

---

## [1.0.0] - 2026-02-23

### Added

- `JustStandardStorage` — abstract interface for non-sensitive key-value storage.
  - `read`, `write`, `delete`, `clear`, `containsKey`
  - `readAll()` — returns all key-value pairs as an unmodifiable map
  - `readJson<T>` / `writeJson<T>` typed JSON helpers
  - `watch(key)` — reactive broadcast stream (emits current value on subscription, then every subsequent change)

- `JustSecureStorage` — abstract interface for encrypted key-value storage.
  - Same read/write/delete/clear/containsKey/readAll/JSON/watch surface as `JustStandardStorage`

- `JustStorage` — factory class for obtaining storage instances.
  - `JustStorage.standard([Directory?])` → `Future<JustStandardStorage>` — returns a `FileStorage` instance backed by the platform's application support directory.
  - `JustStorage.encrypted([Directory?])` → `Future<JustSecureStorage>` — returns an `EncryptedFileStorage` instance backed by the platform's application support directory.
  - Both methods accept an optional `Directory` override for testing.

- `FileStorage` — `JustStandardStorage` implementation backed by `dart:io`.
  - Persists to `<directory>/just_storage.json`
  - Atomic writes via rename-swap (`<name>.tmp` → target)
  - In-memory cache; lazy initialisation on first use
  - `StreamController.broadcast(sync: true)` per key for zero-latency `watch()` delivery

- `EncryptedFileStorage` — `JustSecureStorage` implementation backed by `dart:io` + AES-256-GCM.
  - Persists to `<directory>/just_secure_storage.enc`
  - AES-256-GCM via `pointycastle` — authenticated encryption; any tampered byte causes `StorageException`
  - Per-value random 12-byte nonce (fresh on every `write`) — nonce reuse is prevented by design
  - Master key (`StorageKeyManager`) auto-generated with `Random.secure()`, stored at `<directory>/.storage.key` with `chmod 600` on POSIX
  - Atomic writes via rename-swap
  - Buffered, causally-ordered `watch()` stream

- `StorageKeyManager` — manages the 256-bit AES master key lifecycle.
  - Generates and persists the key on first use
  - Validates key file size on load (throws `StorageException` on corruption)
  - `destroy()` — secure key wipe for full data-erasure scenarios

- `AesGcmCipher` — thin, tested wrapper over `pointycastle`'s `GCMBlockCipher(AESEngine())`.
  - `encrypt(key, nonce, plaintext)` → `ciphertext || 16-byte GCM tag`
  - `decrypt(key, nonce, ciphertextWithTag)` → plaintext, or throws `StorageException` on tag failure
  - `AesGcmCipher.randomNonce()` — generates a cryptographically-random 12-byte nonce

- `StorageException` — typed exception wrapping underlying errors with `message` and optional `cause`.

### Dependencies

- `path_provider: ^2.1.2` — resolves the app-private support directory
- `pointycastle: ^3.7.3` — AES-256-GCM cryptographic primitives
