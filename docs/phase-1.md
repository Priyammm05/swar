# Phase 1 desktop shell

Phase 1 turns the architecture health check into Swar's first product-shaped desktop shell. It still uses fake repositories and sample values. Audio capture, native shortcuts, real history, search indexing, copy, editing, and model management remain outside this phase.

## Included

- Responsive desktop navigation for Dictation, Insights, General Settings, and System Settings
- A lazily built history representing 10,000 fake dictations
- Repository-backed sample search and language filtering
- Empty history state
- Clearly labelled preview insights
- General and System controls backed by an in-memory settings repository
- The Rust system check under System Settings
- Widget tests and a synthetic desktop user journey
- A boundary check that prevents presentation code from importing the generated Rust bridge

## Architecture boundary

Flutter owns rendering, navigation, accessibility, and short-lived presentation state. Repository contracts keep the UI independent of storage and native code. Rust will own real history queries, audio, inference, insertion, and the dictation state machine. Raw PCM will not cross into Dart. Dart isolates are reserved for measured heavy work that genuinely remains in Dart.

Cargokit uses the pinned Rust 1.88.0 toolchain for debug and release native builds. This keeps the compiler used by Flutter builds aligned with Rust CI instead of following a moving stable channel.

The Phase 1 fake history applies its query inside the repository. This mirrors the future Rust and SQLite boundary and prevents Flutter widgets from loading or scanning the full dataset.

## Acceptance evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| Flutter analysis and widget tests | Complete locally | Static analysis and eight tests pass |
| Flutter presentation boundary | Complete locally | `verify_flutter_boundaries.sh` passes |
| Rust formatting, Clippy, and tests | Complete locally | Rust 1.88.0 checks pass |
| macOS synthetic-user journey | Complete locally | Search, responsive navigation, settings, lifecycle recovery, and the real Rust stream pass |
| Universal 2 macOS release | Complete locally | Release executable contains `x86_64` and `arm64` |
| Windows synthetic user and x64 release | Pending | Must run on Windows CI after these local changes are published |
| Individual human sessions | Pending | Required on representative macOS and Windows hardware before public release |

Run the deterministic checks:

```sh
cd apps/swar_desktop
flutter analyze
flutter test
cd ../..
./scripts/verify_flutter_boundaries.sh
./scripts/verify_user_testing_framework.sh
```

Run the real desktop synthetic user:

```sh
./scripts/run_synthetic_user_test.sh macos
```

Windows CI runs the same journey with `windows`. A phase is not ready for public release until both platform journeys pass and the task-based human scenario has been completed on representative hardware.

## Next engineering slice

Phase 2 moves history and insights into Rust-backed SQLite APIs with migrations, pagination, full-text search, filters, copy, edit, delete, retention, and repository tests. Audio remains a later, separate slice.
