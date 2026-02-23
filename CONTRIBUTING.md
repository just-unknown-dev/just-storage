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

**Prerequisites**: [Dart SDK](https://dart.dev/get-dart) ≥ 3.0 or
[Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.10.

```bash
# From the package root
dart pub get
```

The package has no generated code, so no additional build steps are required.

---

## Coding guidelines

- Follow the official [Dart style guide](https://dart.dev/guides/language/effective-dart/style).
- Format code with `dart format .` before committing.
- All public symbols must have doc comments (`///`).
- Avoid adding new dependencies without prior discussion — the package is
  deliberately minimal (`dart:io`, `path_provider`, `pointycastle` only).
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

## Development Setup

| Tool | Minimum version | Recommended version |
|------|-----------------| --------------------|
| Flutter | 1.17.0 | 3.41.1 |
| Dart SDK | 3.11.0 | 3.11.0 |

The repository is a **Flutter package**. You can develop and test it using the companion admin app located at the workspace root.

## Running tests

```bash
# From the package root
dart test
```

To run a single test file:
```bash
dart test test/just_storage_test.dart
```

The test suite uses real temporary directories (`Directory.systemTemp`) — no
mocking of `dart:io` is required. Tests clean up after themselves via
`tearDown`.

### Writing tests

- Place new tests in `test/just_storage_test.dart` under the appropriate
  `group`.
- Cover both the happy path and relevant error cases (`StorageException`).
- For `EncryptedFileStorage` tests, verify tamper detection (GCM tag
  mismatch) where applicable.

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
