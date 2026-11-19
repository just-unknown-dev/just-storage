# Contributing to just_storage

Thank you for taking the time to contribute! 🎉  
This document covers everything you need to know to get started.

---

## Table of contents

- [Code of Conduct](#code-of-conduct)
- [Getting started](#getting-started)
- [How to contribute](#how-to-contribute)
  - [Reporting bugs](#reporting-bugs)
  - [Suggesting features](#suggesting-features)
  - [Submitting a pull request](#submitting-a-pull-request)
- [Development setup](#development-setup)
- [Coding guidelines](#coding-guidelines)
- [Commit messages](#commit-messages)
- [Running tests](#running-tests)
- [Versioning & changelog](#versioning--changelog)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating you agree to abide by its terms.

---

## Getting started

1. **Fork** the repository and clone your fork.
2. Create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
3. Make your changes, write tests, and verify everything passes (see
   [Running tests](#running-tests)).
4. Open a pull request against `main`.

---

## How to contribute

### Reporting bugs

Before opening a new issue, please search the
[existing issues](../../issues) to avoid duplicates.

When filing a bug report, include:

- **just_storage version** (from `pubspec.yaml`)
- **Dart / Flutter SDK version** (`dart --version`)
- **Platform** (Android / iOS / Linux / macOS / Windows / Web)
- A **minimal reproducible example** — the smallest amount of code that
  demonstrates the problem
- The **actual** vs. **expected** behavior
- Any relevant stack traces

### Suggesting features

Open an issue with the label `enhancement` and describe:

- The problem your feature solves
- Your proposed API (code snippet preferred)
- Any alternatives you considered

### Submitting a pull request

- Keep PRs focused — one logical change per PR.
- Add or update tests to cover your change.
- Update the relevant documentation (inline doc comments, README, CHANGELOG).
- Ensure `dart analyze` reports no errors or warnings.
- Ensure all tests pass (`dart test`).
- Reference the related issue in the PR description (e.g. `Closes #42`).

A maintainer will review your PR as soon as possible. Please be patient — we
may ask for changes or clarification.

---

## Development setup

**Prerequisites**: [Flutter SDK](https://flutter.dev/docs/get-started/install)
≥ 3.47.1 (Dart ≥ 3.11). It is a Flutter package: use `flutter`, not `dart`,
for `pub get` and `test`.

```bash
# From the package root
flutter pub get
```

The package has no generated code, so no additional build steps are required.

### Layout

`lib/src/` is cut by feature, in layers; `test/library_layout_test.dart`
checks it:

| Folder | What | May import |
|---|---|---|
| `core/` | The storage types, the exceptions, what every platform shares | Dart, `flutter/foundation.dart` |
| `file/` | Native platforms: files, pointycastle | `core/`, `dart:io` |
| `web/` | The web: `localStorage`, Web Crypto, IndexedDB | `core/`, `package:web` |
| `ui/` | The admin screen | `core/`, `file/` or `web/`, Flutter |

Each folder has a barrel named after it; a file the public libraries don't
export marks its declarations `@internal`.

---

## Coding guidelines

- Follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style).
- Format code with `dart format .` before committing.
- All public symbols must have doc comments (`///`).
- Avoid adding new dependencies without prior discussion — the package is
  deliberately minimal (`path_provider`, `pointycastle` and `web` only).
- Never let a storage overwrite data it couldn't read: throw a
  `StorageCorruptException` and leave it for `clear()`.
- Prefer immutability and pure functions where practical.
- All `StorageException` messages should be human-readable and include the
  offending key where applicable.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.

Examples:
```
feat(encryption): support ChaCha20-Poly1305 as an alternative cipher
fix(file_storage): handle concurrent writes on Windows
docs(readme): add DI registration example for Riverpod
```

---

## Running tests

```bash
# From the package root
flutter test
```

To run a single test file:
```bash
flutter test test/file/file_storage_test.dart
```

The native tests use real temporary directories (`Directory.systemTemp`) — no
mocking of `dart:io` is required — and clean up after themselves. The tests
under `test/web/` run in a browser:

```bash
flutter test --platform chrome test/web
```

`example/example.dart` is a small app that writes some values and opens the
admin screen.

### Writing tests

- Tests mirror `lib/src/`: `test/core/`, `test/file/`, `test/web/`,
  `test/ui/`.
- Behaviour every storage shares goes in `test/support/storage_contract.dart`,
  which each implementation's test runs.
- Cover both the happy path and the error cases (`StorageException`,
  `StorageCorruptException`), and check that a storage leaves data it can't
  read untouched.
- For the secure storages, check tamper detection (a changed value, a value
  moved to another key) where it applies.

---

## Versioning & changelog

This package follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

| Change | Version bump |
|---|---|
| Breaking API change | `MAJOR` |
| New backward-compatible feature | `MINOR` |
| Bug fix or internal improvement | `PATCH` |

Update [CHANGELOG.md](CHANGELOG.md) in the **Unreleased** section with a brief
description of your change. A maintainer will assign the version number when
the release is cut.
