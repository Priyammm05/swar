# Swar feature, testing, and release workflow for Claude

This file is the operational guide for Claude when implementing or testing a Swar feature. Read it before changing source code or running a release workflow.

The engineering rules in `AGENTS.md` are mandatory. The product requirements in `swar.md` and `swar_addition.md` remain the product source of truth. `swar_session_impl.md` records the current implementation, architecture, reference projects, verified behavior, and known gaps.

## 1. Start every task by establishing the baseline

Before editing anything:

1. Read `AGENTS.md` completely.
2. Read the relevant sections of `swar.md`, `swar_addition.md`, and `swar_session_impl.md`.
3. Run `git status --short` and preserve every existing user change.
4. Inspect the current implementation and its nearest tests.
5. State the exact user-facing outcome being changed.
6. Identify whether Flutter, Rust, macOS, Windows, or more than one layer owns the behavior.
7. Define the manual acceptance check before implementation.

Do not change unrelated UI, architecture, dependencies, model files, settings, or release metadata while implementing a narrow feature.

## 2. Respect Swar's ownership boundaries

### Flutter owns

- the Dictation and Insights pages;
- General and System Settings;
- lightweight view models and rendering;
- typed lifecycle events;
- deterministic shortcut gesture reduction.

Flutter must not process PCM, run inference, hash model files, or perform large database work. Raw PCM must never cross into Dart.

### Rust owns

- the dictation state machine and coordinator;
- capture, pre-roll, resampling, speech detection, and audio levels;
- model installation, hashing, and warm model ownership;
- ASR, deterministic cleanup, protected-token validation, and enhancement routing;
- clipboard orchestration and insertion status;
- SQLite history, Insights, vocabulary, and learning data;
- benchmarks and privacy-safe stage diagnostics.

### Native platform code owns

- global keyboard hooks;
- focused-application context;
- microphone and Accessibility permission integration;
- non-activating overlays;
- menu-bar, Dock, tray, and window lifecycle behavior;
- operating-system text insertion primitives.

Keep platform interfaces narrow. Do not move an operating-system responsibility into Flutter for convenience.

## 3. Feature implementation order

Use this order for one feature:

1. Confirm the feature scope and acceptance behavior.
2. Trace the existing end-to-end path before modifying it.
3. Implement the smallest coherent source change.
4. Make a runnable development or release build so the behavior can be observed.
5. Add targeted regression tests after the behavior is implemented.
6. Run the fast automated framework.
7. Build, sign, and install a release candidate when native behavior is involved.
8. Launch the installed application and complete the real user task.
9. Convert every reproduced failure into a narrow regression test when practical.
10. Run the full framework before calling the feature release-ready.
11. Update the relevant compatibility, model, architecture, scenario, or session documentation.
12. Commit the work in small capability-sized commits with descriptive subjects and bodies.
13. Push only after the user authorizes it and the working tree is understood.

Do not call a feature complete because it compiles or because a smoke test passed.

## 4. Targeted testing while implementing

Run the narrowest relevant tests first.

### Rust logic

```sh
cargo test -p swar_core module_name::tests
```

If `cargo` is not already on `PATH`, use `./scripts/run_test_framework.sh fast`. That script discovers the configured Rust toolchain.

### Flutter unit and widget behavior

```sh
cd apps/swar_desktop
flutter test test/path_to_test.dart
```

### Flutter formatting and analysis

```sh
cd apps/swar_desktop
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
```

### Architecture boundaries

```sh
./scripts/verify_flutter_boundaries.sh
./scripts/verify_user_testing_framework.sh
```

## 5. Automated framework

During iteration, run:

```sh
./scripts/run_test_framework.sh fast
```

The fast framework covers Rust formatting, checking, Clippy, Rust tests, Flutter boundary rules, user-test plan validation, Dart formatting, Flutter analysis, and Flutter unit and widget tests.

Before release sign-off, run:

```sh
./scripts/run_test_framework.sh full
```

The full framework adds the local pipeline benchmark, multilingual ASR suite, real Flutter-to-Rust desktop bridge, and synthetic-user journey.

If the configured Flutter SDK is outside the workspace, ask for permission to let the framework update or read its SDK cache. Do not bypass a failed check.

## 6. Synthetic and individual-user testing

Run the automated desktop user independently with:

```sh
./scripts/run_synthetic_user_test.sh macos
```

On Windows, use:

```sh
./scripts/run_synthetic_user_test.sh windows
```

Evidence is written under `apps/swar_desktop/build/user-testing/synthetic-user`.

Start a private real-user dictation session with:

```sh
./scripts/start_user_test.sh phase-2-dictation
```

The session file is stored under `.user-testing/sessions` and must remain ignored by Git. Never commit private audio, dictated text, names, email addresses, clipboard content, API keys, or raw session notes.

For a user-facing feature, test:

- the normal path;
- interruption;
- cancellation;
- failure and recovery;
- repeated use;
- offline behavior;
- focus preservation;
- accessibility and keyboard-only behavior;
- supported window sizes;
- relevant languages;
- the real target applications named in the scenario.

## 7. macOS release build

From `apps/swar_desktop`, build the release application:

```sh
flutter build macos --release
```

If Flutter is not on `PATH`, use the `FLUTTER_ROOT` recorded in `apps/swar_desktop/macos/Flutter/ephemeral/Flutter-Generated.xcconfig`.

Verify the Universal 2 bundle, minimum macOS target, frameworks, and microphone metadata:

```sh
cd ../..
./scripts/verify_macos_bundle.sh
```

Sign nested frameworks and the app with Swar's stable local Accessibility identity:

```sh
./scripts/sign_local_macos.sh
```

Do not change the bundle identifier or signing requirement casually. A changing local identity causes macOS Accessibility permission to be requested again after each build.

## 8. Install and open the macOS release safely

Installing into `/Applications` changes external system state. Ask the user for permission immediately before doing it.

1. Request a normal quit from the existing Swar process.
2. Confirm the process stopped. If it did not, ask before terminating only the Swar process.
3. Copy the signed application into `/Applications`:

```sh
ditto apps/swar_desktop/build/macos/Build/Products/Release/swar.app /Applications/swar.app
```

4. Verify that the installed executable matches the built executable:

```sh
shasum -a 256 \
  apps/swar_desktop/build/macos/Build/Products/Release/swar.app/Contents/MacOS/swar \
  /Applications/swar.app/Contents/MacOS/swar
```

5. Verify the installed signature:

```sh
codesign --verify --deep --strict /Applications/swar.app
```

6. Launch the installed app:

```sh
open -a /Applications/swar.app
```

7. Confirm that `/Applications/swar.app/Contents/MacOS/swar` is the running executable.

Never claim that a newly built release is installed while an older process is still running.

## 9. Real dictation acceptance check

After the installed release opens:

1. Focus a real text field in a native app.
2. Dictate a short English sentence.
3. Dictate a short Hindi sentence.
4. Dictate a natural Hinglish sentence.
5. Repeat in a browser content-editable control.
6. Repeat in an Electron text field such as Codex.
7. Test hold-to-talk and the double-press locked mode.
8. Confirm the overlay never steals focus.
9. Confirm a new recording cannot start while the previous result is finishing.
10. Confirm the final text appears once at the original cursor position.
11. Confirm history refreshes after completion.
12. Confirm silence creates no fake history row.
13. Disconnect the internet and repeat the applicable local checks.

The feature is not accepted until the person confirms the real task works.

## 10. Privacy-safe dictation diagnosis

Swar stores only the last static pipeline stage at:

```text
~/Library/Application Support/dev.Swar.Swar/last_dictation_stage
```

Useful stages include capture, speech detection, transcription, cleanup, insertion, history, and completed. The file must never contain dictated text, clipboard content, audio, or provider errors.

When diagnosing a failure:

1. Record the stage and its modification time.
2. Check whether a new crash report exists under `~/Library/Logs/DiagnosticReports`.
3. Confirm the installed binary hash matches the release build.
4. Confirm automatic paste is enabled without printing secrets.
5. Check clipboard length or a one-way hash if necessary. Do not print its contents.
6. Inspect a narrow process stack sample only when the app appears blocked.
7. Reproduce with sanitized text.
8. Add a regression at the failing boundary.

Examples:

- Stopping at `transcription` points to the model or decoding path.
- Stopping at `cleanup` points to personalization, cleanup, enhancement, or the transition into insertion.
- Reaching `insertion` with a copied fallback points to focus, Accessibility, or the platform paste path.
- Reaching `completed` without a visible history update points to Flutter refresh or repository paging.

## 11. Hinglish feature checklist

Hinglish quality is an ASR and language-policy feature, not a vocabulary-replacement feature. Do not fix ordinary recognition errors by adding hard-coded word substitutions.

Before implementation, ask one product question: should Hindi words in Hinglish appear in Roman script, Devanagari, or follow a user-controlled preference? Audio alone does not uniquely determine the desired writing script.

Then:

1. Build a private, local Hinglish evaluation set containing short commands, natural sentences, names, numbers, and English technical terms.
2. Keep evaluation audio and raw transcripts out of Git.
3. Measure the current multilingual model in Automatic and explicit Hinglish modes.
4. Compare code-switch-capable multilingual model candidates on accuracy, real-time factor, memory, disk size, Intel fallback, and licence.
5. Keep whisper.cpp automatic transcription configured to detect language and continue decoding. Do not enable its detection-only mode.
6. Test whether a restrained Hinglish prompt improves code switching without damaging English or Hindi.
7. Preserve names, numbers, URLs, negation, and mixed-language tokens through cleanup.
8. Do not translate Hindi into English or English into Hindi unless the user requests translation.
9. Add short and long Hinglish benchmark cases plus a real-speaker acceptance scenario.
10. Run English and Hindi regression suites whenever the Hinglish route changes.
11. Pin every selected model revision, checksum, provenance, and licence in `docs/models.md`.
12. Verify the complete recording-to-insertion path in native, browser, and Electron fields.

Do not claim Hinglish support from one synthetic voice fixture. It needs real-speaker evidence and a written script policy.

## 12. Windows release verification

Windows work must retain Windows 10 version 1809 compatibility and a baseline path that does not require AVX or AVX2.

For a Windows release candidate:

1. Run the full framework on Windows.
2. Build the x64 release artifact.
3. Test microphone selection, global shortcuts, the non-activating overlay, UI Automation insertion, and clipboard fallback.
4. Test Windows 10 1809 or the oldest maintained test image, plus current Windows 11.
5. Record the evidence level in `docs/compatibility.md` accurately.

Compilation on macOS is not Windows runtime evidence.

## 13. Commit and push discipline

Before committing:

```sh
git diff --check
git status --short
```

Split work by capability. Good examples are:

- one behavior fix and its focused regression;
- one benchmark or test-framework expansion;
- one platform lifecycle change;
- one documentation handoff.

Each commit needs:

- a concise imperative subject;
- a body describing what changed;
- why it changed;
- the important test or compatibility effect.

Do not use vague subjects such as `phase 1`, `updates`, or `fix stuff`.

After committing:

```sh
git status --short
git log -5 --format=fuller
```

Push only when explicitly authorized:

```sh
git push origin main
```

Never place a GitHub token in source code, shell history, a commit, logs, or chat. Use `./scripts/github_login.sh` and the private credential store described in `README.md` when authentication is required.

## 14. Final handoff format

Tell the user:

1. the exact user-visible outcome;
2. the root cause when fixing a defect;
3. the files or subsystems changed;
4. the tests that passed and those not run;
5. whether a release was built, signed, installed, and launched;
6. the exact manual test to perform;
7. whether changes are uncommitted, committed, or pushed;
8. any remaining compatibility or quality gap.

Never say everything is complete when a required platform, language, benchmark, or real-user check is still pending.
