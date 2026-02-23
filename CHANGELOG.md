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
