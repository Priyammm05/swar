# Phase 1 desktop shell

Phase 1 turns the architecture health check into Swar's first product-shaped desktop application. Production history and insights now come from the private local SQLite store. The native core owns microphone capture, offline Whisper transcription, baseline cleanup, clipboard insertion, and persistence. Fake repositories remain test-only.

## Included

- Responsive desktop navigation with Insights first and Dictation second
- A bounded, paginated local history projection
- SQLite FTS-backed transcript search
- Empty history state
- SQLite-aggregated local insights
- A Settings dialog with General and System controls, offline-model state, and test dictation
- The Rust system check under System Settings
- Widget tests and a synthetic desktop user journey
- A boundary check that prevents presentation code from importing the generated Rust bridge

## Architecture boundary

Flutter owns rendering, navigation, accessibility, and short-lived presentation state. Repository contracts keep the UI independent of storage and native code. Rust will own real history queries, audio, inference, insertion, and the dictation state machine. Raw PCM will not cross into Dart. Dart isolates are reserved for measured heavy work that genuinely remains in Dart.

Cargokit uses the pinned Rust 1.88.0 toolchain for debug and release native builds. This keeps the compiler used by Flutter builds aligned with Rust CI instead of following a moving stable channel.

Rust performs search, aggregation, audio capture, resampling, transcription, cleanup, insertion, and persistence. Flutter receives bounded records, summary values, audio levels, and typed state only. The 10,000-record fake is retained to test bounded loading and rendering without putting production sample data in the app.

## Acceptance evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| Flutter analysis and widget tests | Complete locally | Static analysis and 13 tests pass |
| Flutter presentation boundary | Complete locally | `verify_flutter_boundaries.sh` passes |
| Rust formatting, Clippy, and tests | Complete locally | Rust 1.88.0 Clippy and five tests pass |
| macOS synthetic-user journey | Complete locally | Twelve user-visible checks pass with screenshot evidence |
| Universal 2 macOS release | Complete locally | Executable and Rust framework contain `x86_64` and `arm64` |
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

The native dictation slice now includes verified model installation, persistent settings, a visible record/stop control, a system-wide Control + Space shortcut, macOS Accessibility permission prompting, clipboard-paste insertion with a copy fallback, and a repeatable Swar-versus-Wispr Flow benchmark harness. The macOS build is intentionally distributed outside the Mac App Store sandbox because cross-application keyboard insertion requires user-approved Accessibility access. Microphone audio and transcription remain local.

The next slice adds per-user local vocabulary learning, history editing/deletion/retention, shortcut customization, and real-model microphone journeys on the full compatibility hardware matrix.
