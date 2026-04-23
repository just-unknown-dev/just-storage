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
