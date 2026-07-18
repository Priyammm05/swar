# Phase 0 health check

Phase 0 proves the desktop architecture before product features are added. The diagnostics screen is developer tooling. It is not the final Swar application shell.

## Acceptance status

| Requirement | Status | Evidence |
| --- | --- | --- |
| Flutter runs on macOS | Complete | Local release build and GitHub Actions macOS build |
| Flutter builds on Windows | Complete | GitHub Actions Windows x64 release build |
| Flutter calls Rust | Complete | Native desktop integration test calls `get_core_version()` through `flutter_rust_bridge` |
| Rust streams without blocking Flutter | Complete | Native desktop integration test receives all events emitted by `stream_demo_events()` from a Rust worker thread |
| CI tests both codebases | Complete | Flutter analysis, Flutter tests, Rust formatting, Clippy, and Rust tests |
| CI builds both platforms | Complete | Universal 2 macOS release and Windows x64 release jobs |
| Version metadata exists | Complete | Flutter and Rust are versioned as `0.1.0` |
| Individual-user test framework exists | Complete | Tracked task scenarios, private session reports, issue classification, and a release gate |

## macOS release proof

- Application: `swar.app`
- Architectures: `x86_64` and `arm64`
- Rust framework architectures: `x86_64` and `arm64`
- Minimum macOS version: `10.15`
- Version: `0.1.0+1`

Run the architecture check with:

```sh
./scripts/verify_macos_bundle.sh
```

Run the Phase 0 individual-user plan with:

```sh
./scripts/start_user_test.sh phase-0-foundation
```

The framework is ready, but a release still needs a completed session on each supported platform family. Creating the framework is not evidence that a person has completed the tasks.

## Windows release proof

- Application: `swar.exe`
- Architecture: x64
- Minimum release target: Windows 10 version 1809
- Version: `0.1.0+1`

The Windows build is produced and uploaded by GitHub Actions because the local development machine is macOS.

## What comes next

Phase 1 replaces the diagnostics-first experience with the Dictation, Insights, General Settings, and System Settings shell. The health check moves to System Settings or remains available only in development builds.
