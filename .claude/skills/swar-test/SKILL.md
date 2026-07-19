---
name: swar-test
description: "Run Swar's full testing and verification workflow — functional acceptance, reliability/resource-safety (memory, races, thermal, crashes), the fast/full automated framework, release-build/sign/install, real dictation acceptance, and the release gate. Use whenever asked to test Swar, verify a Swar change, check a feature works, run the framework, or decide if Swar is release-ready. Trigger: /swar-test"
trigger: /swar-test
---

# /swar-test — Swar testing & verification workflow

Operational skill that drives Swar through its real testing workflow. This encodes the rules
in `CLAUDE.md`, `AGENTS.md`, the product specs (`swar.md`, `swar_addition.md`), the current
implementation reality (`swar_session_impl.md`), the `docs/` matrices, and the
`quality/user-testing/` scenarios + scripts. It exists so a feature is never called "done"
because it compiled or a smoke test passed.

## Usage

```
/swar-test fast            # fast automated framework only (iteration loop)
/swar-test full            # full framework (benchmarks + native + synthetic user)
/swar-test feature <name>  # run the ordered per-feature workflow (§B) end to end
/swar-test reliability     # run the reliability & resource-safety pass (§E)
/swar-test release         # full release-readiness pass incl. build/sign/install + gate (§F,§G)
/swar-test dictation       # real recording→insertion acceptance checklist (§D)
```

Default when bare `/swar-test` is given: run **fast**, then report what still needs `full`,
native, and human evidence before release.

## Golden rules (never violate while testing)

1. **Compiling is not passing.** A feature is not done because it builds or a smoke test passed.
2. **Preserve user changes.** `git status --short` first; never discard existing working-tree edits.
3. **Do not widen scope.** No unrelated UI/architecture/dependency/model/settings/release-metadata
   changes while testing a narrow feature.
4. **Ask before external state changes.** Installing into `/Applications`, quitting/terminating the
   Swar process, or pushing to git each need explicit permission immediately before the act.
5. **Never over-claim.** Compilation on macOS is not Windows runtime evidence. A configured/cross-
   compiled target is not runtime-tested. One synthetic voice fixture is not Hinglish support.
6. **Privacy is a hard gate.** Never commit or print dictated text, clipboard contents, raw audio,
   names, emails, API keys, or raw session notes. Logs and the stage file must contain none of these.
7. **Don't bypass a failed check.** Fix it or report it. If the Flutter SDK is outside the workspace,
   ask permission before letting the framework touch its SDK cache.

---

## A. Baseline — do this before any test run

1. Read `AGENTS.md` fully, plus the relevant sections of `swar.md`, `swar_addition.md`,
   `swar_session_impl.md`.
2. `git status --short` — record and preserve every existing user change.
3. State the exact user-facing outcome under test in one sentence.
4. Identify the owning layer(s) (see §C) — this determines which tests are load-bearing.
5. Define the manual acceptance check before running anything.
6. Note which claims are **verified** vs **unverified** today (see §H) so results aren't over-stated.

---

## B. Per-feature ordered workflow (`/swar-test feature <name>`)

Run in this order. Do not skip ahead because an earlier step "looks fine."

1. Confirm feature scope + acceptance behavior.
2. Trace the existing end-to-end path before modifying it.
3. (implementation happens outside this skill — smallest coherent change)
4. Make a runnable dev or release build so the behavior can be observed.
5. Add targeted regression tests **after** the behavior exists.
6. Run the **fast** framework (§Tiers).
7. Build, sign, install a release candidate **when native behavior is involved** (§F).
8. Launch the installed app and complete the real user task (§D).
9. Convert every reproduced failure into a narrow regression test at the failing boundary.
10. Run the **full** framework before calling it release-ready.
11. Update the affected `docs/compatibility.md` / `docs/models.md` / architecture / scenario / session docs.
12. Commit in small capability-sized commits (§I).
13. Push only after explicit authorization and a understood working tree.

---

## Tiers — the automated framework (verbatim commands, run from repo root)

Credential env vars are unset by the framework automatically. All commands run from the repo root
unless noted.

### Fast (iteration loop)
```sh
./scripts/run_test_framework.sh fast
```
Covers, in order: `cargo fmt --all -- --check` · `cargo check --workspace` ·
`cargo clippy --workspace --all-targets -- -D warnings` · `cargo test --workspace --all-targets` ·
`./scripts/verify_flutter_boundaries.sh` · `./scripts/verify_user_testing_framework.sh` · then in
`apps/swar_desktop`: `dart format --output=none --set-exit-if-changed lib test integration_test` ·
`flutter analyze` · `flutter test`.
Pass signal: prints `Swar fast test framework passed.`

### Full (before release sign-off)
```sh
./scripts/run_test_framework.sh full
```
Adds: `./scripts/run_pipeline_microbenchmark.sh 10000`; then on macOS —
`run_asr_benchmark_suite.sh`, `flutter test integration_test/core_bridge_test.dart -d macos`,
`run_synthetic_user_test.sh macos`; on Windows the `-d windows` equivalents.
Pass signal: prints `Swar full test framework passed.`

### Narrowest-first while implementing
```sh
cargo test -p swar_core module_name::tests          # Rust logic (fallback: ./scripts/run_test_framework.sh fast)
cd apps/swar_desktop && flutter test test/<path>.dart
cd apps/swar_desktop && dart format --output=none --set-exit-if-changed lib test integration_test && flutter analyze
./scripts/verify_flutter_boundaries.sh
./scripts/verify_user_testing_framework.sh
```

### Standalone benchmarks / evidence
```sh
./scripts/run_asr_benchmark_suite.sh          # macOS + installed model; WER/RTF thresholds per case
./scripts/run_pipeline_microbenchmark.sh 10000
./scripts/run_synthetic_user_test.sh macos    # evidence → apps/swar_desktop/build/user-testing/synthetic-user
./scripts/start_user_test.sh phase-2-dictation# private session file → .user-testing/sessions (git-ignored, chmod 600)
```

Current verified baseline counts (post macOS-paste-fix): **41 Rust tests**, **29 Flutter unit/widget
tests**, Flutter analysis clean. Treat a drop below these, or a newly skipped suite, as a regression.

---

## C. Ownership boundaries → what each layer's tests must cover

Test at the layer that **owns** the behavior; do not move an OS responsibility into Flutter to make
it easier to test.

- **Flutter owns:** Dictation & Insights pages, General & System Settings, lightweight view models,
  typed lifecycle-event rendering, the deterministic Dart shortcut gesture reducer.
  Flutter must **never** process PCM, run inference, hash models, or do large DB work.
  `verify_flutter_boundaries.sh` fails if presentation code imports the generated Rust bridge.
- **Rust (`swar_core`) owns:** state machine + coordinator; capture/pre-roll/resample/VAD/levels;
  model install + SHA-256 + warm-model ownership; ASR, deterministic cleanup, protected-token
  validation, enhancement routing; clipboard + insertion orchestration; SQLite history/Insights/
  vocabulary/learning; benchmarks; the privacy-safe stage diagnostics.
- **Native (Swift / Win32) owns:** global key hooks, foreground-app context, mic/Accessibility
  permission, non-activating overlays, menu-bar/Dock/tray/window lifecycle, OS text-insertion.

Layering: unit tests prove deterministic rules → synthetic desktop user proves scripted journeys →
human testing catches confusing/trust/latency/naturalness issues. All three are required; no one
substitutes for another.

---

## D. Functional acceptance checklist (real recording → insertion)

Requires an **installed, signed** release with Microphone + Accessibility granted **to Swar itself**,
internet disconnected after model install. Test the normal path plus interruption, cancellation,
failure/recovery, repeated use, offline, focus preservation, accessibility/keyboard-only, supported
window sizes, relevant languages, and the real target apps.

**Core loop**
- [ ] Click field → hold shortcut → speak → release → final text appears **once** at the original cursor.
- [ ] History row appears immediately after completion (page live-updates without reopening).
- [ ] Insights update.

**Languages (mandatory — English, Hindi, Hinglish)**
- [ ] English sentence recognized and inserted.
- [ ] Hindi sentence inserted in **Devanagari** (Unicode inserts correctly; not mapped to English/Hinglish).
- [ ] Natural Hinglish preserved, **not translated** and not normalized to pure English/Hindi.
  Canonical: "Kal Niyo ke Kafka consumer wale PR ko review karna, and check if deployment ready hai."
  Structure may improve; language mixture may not change.
- [ ] Auto mode saves the detected language per dictation.

**Shortcut modes**
- [ ] Hold-to-talk: key-down starts once, keyboard **auto-repeat ignored**, key-up stops.
- [ ] Hands-free toggle (the separate configurable shortcut): starts, runs hands-free, one press ends;
      VAD can end it. (Confirm intended interaction — spec says "toggle", not literally "double-press".)
- [ ] Cancel discards and returns to idle; cancelled dictation does **not** save and is excluded from metrics.
- [ ] A new recording **cannot** begin until transcription, cleanup, insertion, and history finish.

**Overlay / focus**
- [ ] Overlay never becomes key/active; clicking the bar does not remove focus from the editor.
- [ ] Bar stays above normal windows, never covers Dock/taskbar, survives display changes, remembers
      position per display and across restarts. Bar animation does not affect ASR.

**Target apps** (native, browser content-editable, Electron): TextEdit/Notes/Word, Chrome/Safari/Edge,
Gmail/Google Docs/Notion, Slack/WhatsApp Desktop, VS Code/Cursor (named Electron targets — nearest
in-scope equivalent to "Codex").
- [ ] Insertion tiers: AX/UIA → clipboard paste (save/restore) → copy-only fallback
      (`Copied — press paste`, saved as `insertion_failed`).
- [ ] If auto-insert unavailable, the same final text remains on the clipboard and Cmd+V works.
- [ ] Windows elevated/admin target → clear copy-only fallback.

**Silence / offline / hallucination**
- [ ] Silence produces no history row and no hallucinated text; blank audio never appears as
      `[BLANK_AUDIO]` or a fake record. (Regression fixtures: devotional repeats, "like share subscribe"
      boilerplate, repeated tokens.)
- [ ] With internet disconnected after model install: recording, ASR, cleanup, history, Insights,
      dictionary all work; no audio leaves the machine; no account/API key required.

**Paging** (DICT-004): 6 records → all shown, no Show More; exactly 50 → no Show More; >50 → first 50
+ Show More that disappears when empty. List virtualises 10,000+ rows without loading all into memory;
search uses SQLite FTS5 (never search in Dart).

The feature is **not accepted** until the person confirms the real task works.

---

## E. Reliability & resource-safety pass (`/swar-test reliability`)

The ways an app silently gets bad. For each item: know the hazard, the guard, and how to exercise it.

**Companion docs (read both before this pass):**
- `quality/reliability/degradation-test-plan.md` — the stress/timing test plan: infra to build first (delay
  injection env vars, ThreadSanitizer lane, `loom`, soak harness), then P0/P1/P2 cases per category.
- `quality/reliability/findings.md` — the live issue register from the code audit (`R-001`…`R-030`, each with
  `file:line`, verdict, failure scenario, fix). **Check open items here before claiming a reliability pass.**
  As of the last audit the top items are: `R-004` wrong-window paste (private text leak), `R-001` coordinator
  reservation leaked on panic (silent dead app), `R-003` ASR `recv()` no timeout (subsystem hang),
  `R-002` preview-spawn `.expect` poisons the capture mutex. Four cross-cutting root causes drive most of
  them: no RAII release for the reservation; `.expect` on `thread::spawn` under a held mutex; no timeout on
  cross-boundary waits; no `catch_unwind` at the whisper FFI boundary.

**Memory**
- [ ] Raw PCM never crosses into Dart (`verify_flutter_boundaries.sh`; AGENTS rule 2). Audio path is
      OS callback → Rust lock-free `rtrb` ring buffer → worker → ASR → small transcript events → Flutter.
- [ ] Audio buffer is **bounded** with a max-dictation-duration guard; zeroed and released after
      finalisation; no audio saved by the release pipeline.
- [ ] History/DB never loads all rows: paginate from SQLite (first page 50), FTS5 search, pre-aggregated
      `daily_metrics`. Exercise with 100,000 synthetic records — UI must not load all rows.
- [ ] Warm-model memory tiers respected: **never hold ASR + LLM decoding concurrently on the 8 GB tier**
      (finish ASR, then cleanup); 16 GB+ may keep LLM warm with a 10-min idle timeout; battery-saver
      unloads after idle. Check peak-RAM budgets; models use mmap. *(Gap: full tier policy / mmap proof /
      idle-timeout scheduling are listed as not-yet-implemented — verify before claiming.)*
- [ ] No model load between shortcut release and insertion on the warm path (AGENTS addition 26).

**Races / concurrency**
- [ ] No two active recording sessions; recording is exclusive.
- [ ] **Spec-vs-impl contradiction — state which you are testing.** Spec (`swar_addition.md`,
      `docs/architecture.md`): sessions pipeline; a new recording may start during Cleaning/Inserting;
      insertions execute in completion order per target. Impl (`swar_session_impl.md` §5.6): coordinator
      is **deliberately reserved** until insertion + history finish, so output cannot overlap/reorder.
      The current scenarios (DICT-002) assert the impl lockout. Do not report a pipelining test as passing
      against the serialized implementation.
- [ ] Clipboard mutex: two Swar operations never change the clipboard at once; restore only when Swar
      still owns the value, and not too early (macOS restoration is currently **disabled** by design —
      dictated text is left on the clipboard as the reliable fallback).
- [ ] Key-down/up + auto-repeat: begins once per gesture; events during final transcription/insertion are
      discarded; a physically held Option key cannot leak into the paste chord (private event source).
- [ ] Worker threads: preview worker stopped and joined, native capture drained on finish.
- [ ] Thread budget: ≤8 ASR threads, always leaving ≥1 core for the desktop; separate thread pools.
- [ ] State machine is the source of truth; only legal transitions; cancellation only before
      post-processing; any stage may move to `failed` where permitted.

**Battery / thermal / CPU**
- [ ] Performance modes (Automatic/Battery saver/Balanced/Maximum) behave; battery saver unloads on idle.
- [ ] RTF is the sustained-CPU proxy — watch the ASR benchmark RTF column (Turbo was rejected at 1.21).
      Always-warm heavy/turbo models must not be defaulted where they can't sustain (8 GB M1, AVX-less Win).
- [ ] Update-rate throttles hold: audio meter ≤30 Hz (native calc 20 windows/s), partial transcript
      3–6 events/s and only-on-change, preview ~1/s. UI stays 60 FPS, no jank during ASR; bar animation
      does not touch ASR. `RepaintBoundary`, fixed waveform point count, no continuous blur on low-end.

**Crash / hang / deadlock**
- [ ] Crash-during-X recovery: model download, verification, recording, final ASR, DB write, clipboard
      replacement, app update. Clipboard must not stay overwritten after a recoverable failure; app update
      preserves DB + models; download resumes after crash.
- [ ] macOS worker-thread paste crash is fixed and locked by regression (exact CG key sequence
      Cmd↓, V↓, V↑, Cmd↑). Enigo keyboard imports compile only off-macOS; macOS uses raw Core Graphics
      virtual key codes; 100 ms wait after publishing the pasteboard; AX direct-write removed. Never
      reintroduce Enigo's TSM/layout path on macOS.
- [ ] Overlay/focus never deadlocks or steals focus while Flutter/Rust work.
- [ ] "App appears blocked" → take a **narrow** process stack sample only then; diagnose via the static
      stage label; add a regression at the failing boundary. Panic handling is not documented beyond
      crash-recovery acceptance — treat "never crashes after finishing transcription" as the bar.

**Resource leaks / cleanup**
- [ ] Every native resource has explicit ownership + teardown.
- [ ] Device unplug / Bluetooth route change / sample-rate change / permission revoked / device busy all
      handled; automatic fallback to default mic. *(Gap: device hot-plug validation listed as remaining.)*
- [ ] Cancel frees the ASR session (`cancel`/`unload`).
- [ ] Downloads use a `.part` temp file, hash while downloading, atomic rename after verify, delete
      corrupt partials, reject path traversal, ≥1.5× free-space check.

**Data integrity**
- [ ] Every schema change ships a migration + migration test; app update preserves DB.
- [ ] Model install is atomic; every model file passes SHA-256 (digests pinned in `docs/models.md`);
      all three pack files must be present + valid before "installed" is reported.
- [ ] History row + daily metrics written transactionally.

---

## F. macOS release build / sign / install (ask before installing)

```sh
cd apps/swar_desktop && flutter build macos --release      # FLUTTER_ROOT in macos/Flutter/ephemeral/Flutter-Generated.xcconfig if not on PATH
cd ../.. && ./scripts/verify_macos_bundle.sh               # Universal 2 (arm64+x86_64), LSMinimumSystemVersion 10.15, NSMicrophoneUsageDescription
./scripts/sign_local_macos.sh                              # ad-hoc sign; stable requirement identifier "dev.swar.desktop" (keeps Accessibility permission)
```
Do **not** change the bundle identifier or signing requirement casually — a changing local identity
re-triggers the macOS Accessibility prompt each build.

Install (ask permission immediately before — this changes system state):
1. Request a normal quit of the running Swar; confirm it stopped (ask before terminating only the Swar process).
```sh
ditto apps/swar_desktop/build/macos/Build/Products/Release/swar.app /Applications/swar.app
shasum -a 256 apps/swar_desktop/build/macos/Build/Products/Release/swar.app/Contents/MacOS/swar /Applications/swar.app/Contents/MacOS/swar
codesign --verify --deep --strict /Applications/swar.app
open -a /Applications/swar.app
```
Confirm `/Applications/swar.app/Contents/MacOS/swar` is the running executable. Never claim a new
release is installed while an older process is still running.

**Windows release** retains Win10 1809 + non-AVX/AVX2 baseline: run full framework on Windows, build
x64, test mic selection / global shortcuts / non-activating overlay / UI Automation insertion /
clipboard fallback on Win10 1809 (or oldest maintained image) + current Win11, record evidence in
`docs/compatibility.md`. Compilation on macOS is not Windows runtime evidence.

---

## G. Release gate (`/swar-test release`) — all applicable statements must be true

- **Automated:** unit/widget/integration/native/build checks pass; synthetic-user journeys pass on
  macOS **and** Windows with reports + screenshots retained; known repeatable defects have regression
  coverage; macOS + Windows **release** artifacts (not just debug) tested.
- **Individual-user:** every changed user-facing flow has a stable scenario + ≥1 clean uncoached session;
  both platforms covered when behavior differs; older OS/hardware covered when compatibility-sensitive;
  accessibility/interruption/failure/recovery/offline checked; **no open S0 or S1**; every open S2 has a
  written release decision.
- **Privacy:** raw session notes stay local; shared findings carry no personal audio/transcript;
  offline behavior checked; recording/processing/storage/insertion states clear to the tester.
- **Sign-off:** record tested build, scenario IDs, platforms, sanitized issue IDs, and the deciding person.
  A passing CI run alone does **not** satisfy the gate.

**Severity:** S0 privacy breach / data loss / unintended insertion · S1 core task blocked, no recovery ·
S2 works only via costly workaround · S3 non-blocking friction · S4 cosmetic. **S0/S1 block release.**

Scenarios: `phase-0-foundation` (PH0-001..005), `phase-1-shell` (SHELL-001..003),
`phase-2-dictation` (DICT-001..005). Each scenario file must contain `## Task <ID>:`,
`### Success criteria`, `### Observe`, `## Session completion` (enforced by
`verify_user_testing_framework.sh`).

---

## H. Verified vs unverified today — don't over-claim

**Verified:** macOS Apple-Silicon dictation → paste path; the exact insertion key sequence; 41 Rust /
29 Flutter tests (fast framework); local packaging + signing; the 6 ASR regression fixtures.

**Unverified / not yet proven:** all Windows runtime behavior; Intel Mac + Catalina runtime;
production ASR accuracy (especially Hindi/Hinglish — synthetic voices only, not real speakers);
a full-framework run against the final insertion source; the cross-app paste matrix; System Settings
switch side effects (launch-at-login, Dock visibility, muting, sounds, notifications); Insights per-app
category factualness.

**Do not assume these work — they are gaps, not features:** pipelined concurrent sessions; an embedded
LLM cleanup model (`EmbeddedLocalEnhancer` is a deterministic editor, **not** an LLM — no llama.cpp
runtime); history row actions (copy/reinsert/delete in the UI); macOS clipboard restoration; AX
direct-write insertion; trained per-user model; onboarding/permission-health flow; model-download
progress/failure/resume UX.

Model facts are pinned in `docs/models.md` (Whisper small q5_1, Hindi Ukta small, Silero v6.2 — each by
exact SHA-256). No model may be advertised as accurate for Hindi until it passes the physical-speaker matrix.

---

## I. Privacy, diagnosis, commit & handoff

**Privacy-safe diagnosis:** the only persisted stage marker is a static label at
`~/Library/Application Support/dev.Swar.Swar/last_dictation_stage` — it must never contain dictated
text, clipboard content, audio, or provider errors. Diagnosis steps: record the stage + mtime; check
`~/Library/Logs/DiagnosticReports` for a new crash; confirm the installed binary hash matches the
build; confirm auto-paste is on without printing secrets; check clipboard length or a one-way hash only;
sample a process stack **only** when the app looks blocked; reproduce with sanitized text; add a
regression at the failing boundary. Stage hints: stop at `transcription` → model/decoding; stop at
`cleanup` → personalization/cleanup/enhancement/transition; `insertion` with copied fallback → focus/
Accessibility/paste path; `completed` with no history update → Flutter refresh / repository paging.

**Never commit or print:** private audio, dictated text, names, emails, clipboard content, API keys,
raw session notes. `.user-testing/sessions` stays git-ignored. Keep Hinglish eval audio + transcripts
out of git. Never put a GitHub token in source, history, commits, logs, or chat — use
`./scripts/github_login.sh`.

**Commit discipline:** `git diff --check` and `git status --short` before; split by capability; each
commit has an imperative subject + a body stating what/why/test-or-compat effect. No vague subjects
(`phase 1`, `updates`, `fix stuff`). After: `git status --short` and `git log -5 --format=fuller`.
Push (`git push origin main`) only when explicitly authorized.

**Final handoff — always tell the user:** (1) the exact user-visible outcome; (2) root cause if fixing a
defect; (3) files/subsystems changed; (4) tests that passed and those not run; (5) whether a release was
built/signed/installed/launched; (6) the exact manual test to perform; (7) uncommitted vs committed vs
pushed; (8) any remaining compatibility/language/benchmark/real-user gap. Never say everything is
complete while a required platform, language, benchmark, or real-user check is still pending.
