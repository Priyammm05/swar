# swar

Swar is a private, offline voice keyboard for macOS and Windows.

## Compatibility

- macOS 10.15 and newer on Intel and Apple Silicon
- Windows 10 version 1809 and newer on x64

See [`docs/compatibility.md`](docs/compatibility.md) for the release matrix and hardware fallback policy.

The platform icon roles and regeneration process are documented in [`docs/icons.md`](docs/icons.md).

## Prerequisites

- Flutter 3.35 or newer
- Rust 1.88 or newer
- `flutter_rust_bridge_codegen` 2.12.0

## Generate the bridge

```sh
./scripts/generate_bridge.sh
```

## Verify

```sh
cd apps/swar_desktop
flutter analyze
flutter test
cd ../..
cargo test --workspace
./scripts/verify_user_testing_framework.sh
```

## Test as a user

Automated checks are only one part of Swar's quality system. Every user-facing feature also needs a synthetic-user journey and a task-based human scenario that check clarity, recovery, trust, latency, and whether Swar preserves the person's voice.

Run Swar's automated synthetic user with:

```sh
./scripts/run_synthetic_user_test.sh
```

Start a private local session with:

```sh
./scripts/start_user_test.sh phase-1-shell
```

The session report is written under `.user-testing/`, which Git ignores because notes may contain personal information. See [`quality/user-testing/README.md`](quality/user-testing/README.md) for the workflow and release gate.

## Version

The initial architecture milestone is `0.1.0`. Flutter package metadata and the Rust core use the same semantic version. CI produces a Universal 2 macOS application and a Windows x64 release bundle for every commit.

See [`docs/phase-0.md`](docs/phase-0.md) for the completed architecture health-check evidence.

Phase 1 now has the responsive product shell, local SQLite history and insights, the native audio/transcription boundary, and automated user journeys. See [`docs/phase-1.md`](docs/phase-1.md) for its scope and acceptance checks.

## GitHub access on restricted laptops

Never save a GitHub token in this repository or paste it into a chat.

Authenticate locally through GitHub CLI:

```sh
./scripts/github_login.sh
```

The token is stored in `~/.swar/.git-credentials` with owner-only permissions. It is separate from Oynix credentials. The fine-grained token needs access to the selected repository, Metadata read permission, and Contents read and write permission.

If normal Git transport is blocked, publish the workspace through the GitHub HTTPS API:

```sh
./scripts/github_api_publish.sh OWNER/REPOSITORY "Initial Swar build"
```

The API publisher creates one commit, does not call `git push`, and respects all `.gitignore` rules.
