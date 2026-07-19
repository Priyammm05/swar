# Swar Reliability & Silent-Degradation Test Plan

**Scope:** The failure classes that automated unit tests routinely miss and that a resident, always-on desktop audio app is uniquely exposed to — race conditions, memory growth, battery/thermal drain, CPU pinning, hangs, and crash paths.

**Why this document is separate from the handoff:** The engineering handoff (section 13) lists *feature* gaps. This document lists *degradation* gaps — the ways Swar can pass every unit test, install cleanly, work in a demo, and still slowly become unusable on a real machine over hours or days. These bugs are timing-, duration-, and load-dependent, so they need deliberate stress harnesses, not more happy-path assertions.

**How to read the priority tags:**
- `P0` — can reach real users and is severe (silent dead app, wrong-window paste, machine heats up). Write these first.
- `P1` — degrades the experience over a session; likely but recoverable.
- `P2` — edge hardware / long-tail; validate before broad release.

**Architectural context this plan assumes** (from the current build): a realtime CPAL audio callback writes into an `rtrb` ring buffer; one named Rust worker owns and reuses a single warm Whisper context; the coordinator is deliberately reserved until insertion **and** history finish (sessions are serialized, not pipelined); macOS paste uses raw Core Graphics virtual key codes after a 100 ms pasteboard settle; clipboard restoration is currently disabled; Flutter never receives raw PCM and refreshes history on a completion event.

---

## 1. Test infrastructure to build first

Races and slow degradation do not reproduce on demand. Before writing individual cases, build the seams that make them reproducible and observable. Without these, every test below is flaky and every result is anecdotal.

### 1.1 Deterministic delay injection (dev-only, env-gated)

Add compile- or env-gated artificial delays at each stage boundary so interleavings can be *forced* rather than hoped for. At minimum:

- `SWAR_TEST_SLOW_ASR_MS` — stall the ASR worker N ms mid-decode.
- `SWAR_TEST_SLOW_PASTE_MS` — delay between pasteboard write and Cmd+V.
- `SWAR_TEST_SLOW_HISTORY_MS` — delay the SQLite commit after the completion event is emitted.
- `SWAR_TEST_STALL_CONSUMER_MS` — block the ring-buffer reader to force overrun.

These must be impossible to enable in a release build. Gate them behind a `#[cfg(debug_assertions)]` or a dedicated `test-hooks` Cargo feature that the release pipeline never sets, and add a test asserting the release binary ignores the env vars.

### 1.2 Instrumentation counters exposed to tests

Surface as readable metrics (they can stay internal in release): dropped-sample count, ring-buffer high-water mark, coordinator-reserved duration per session, warm-context load count, worker-thread count currently alive, and peak RSS. Several already exist (dropped-sample and stream-error counters) — extend the set and make them assertable from the test harness.

### 1.3 Standing analysis builds

- **ThreadSanitizer build of `swar_core`.** Single highest-leverage addition in this document. TSan finds data races that no logic test will. Add a CI lane (`cargo +nightly test -Z sanitizer=thread` on the core, or the stable equivalent for your toolchain) even if it only runs nightly.
- **AddressSanitizer / LeakSanitizer build** for the FFI boundary into whisper.cpp — that C/C++ edge is where leaks and use-after-free hide.
- **`loom` model-checking** on the coordinator reservation + activation-lock state machine specifically. That logic is small, critical, and concurrency-defining — exactly what loom is for.

### 1.4 Soak-test harness

A scripted synthetic user that runs **hundreds to thousands of dictation cycles unattended**, with randomized timing (release points, double-press gestures, cancels), while recording the counters from 1.2 over time. Most degradation bugs only appear after N iterations; a single-shot test will pass forever while the app leaks.

---

## 2. Race conditions

### 2.1 Audio callback ↔ ring buffer (the realtime boundary) — P0

The most dangerous zone: one side is a realtime OS callback that must never block.

- **Overrun under slow consumer.** Stall the reader (`SWAR_TEST_STALL_CONSUMER_MS`) and confirm the writer drops cleanly, the dropped-sample counter fires, and there is no glitch, panic, or unbounded growth. `rtrb` being lock-free prevents priority inversion — it does **not** prevent logical overrun. Verify the overrun *policy* is correct, not just that it doesn't crash.
- **Underrun on the read side** when speech is sparse — confirm the worker handles an empty read without busy-spinning (see CPU pinning, §5).
- **Callback firing after teardown.** Stop/join the worker while the OS still has a callback in flight. Confirm no write to a freed buffer. This is a use-after-free candidate — run it under TSan/ASan.
- **Allocation or logging in the callback.** Audit that the realtime path only reads, converts minimally, pushes, and returns. Any `malloc`, mutex, or log call on that path is a latent glitch/priority-inversion bug even if it never shows in a test.

### 2.2 Preview worker ↔ finalisation over the shared Whisper context — P0

The finish flow stops and joins the preview worker, then finalises. The race: the preview worker is mid-decode holding the single warm context when finalise wants it.

- Tight loop: release the shortcut *exactly* as a ~1 s preview snapshot begins decoding. Confirm finalise blocks on the join correctly and two decodes never touch one context concurrently.
- Assert the join actually completes before the final beam-search decode starts (not merely that a stop was signalled).
- Run under TSan — a context touched by two threads is the textbook data race here.

### 2.3 Coordinator reservation / activation lock — P0

Sessions are serialized by holding the coordinator until insertion + history finish. Two things to prove:

- **Lock holds under gesture spam.** Hammer down/up/double-press/cancel during `finalising`, `transcribing`, `cleaning`, and `inserting`. Every event in those windows must be discarded; no second session may start; no event may be *queued* and fire late after completion.
- **Lock ALWAYS releases — including on every failure and crash-recovery path.** This is the P0-of-P0s: if a failed insertion, a rejected enhancement (`swar-INTENT-004`), a device loss, or a panic leaves the coordinator reserved, the app **silently stops recording forever** until relaunch, while still looking alive. Write an explicit test per failure branch asserting the coordinator returns to idle. Fault-inject a panic mid-insertion and confirm recovery.

### 2.4 Insertion timing & focus change — P0

The one that already bit you (the `TSMGetInputSourceProperty` off-queue crash). Beyond the fix already in place:

- **Focus changes between "capture foreground app" and "send Cmd+V."** User Alt-Tabs, or an app steals focus, during finalisation. Confirm Swar pastes only into the *validated, still-existing* target, or falls back to clipboard — **never** pastes dictation into the wrong window. Wrong-window paste can leak private text into a chat/address bar; treat it as severe.
- **Slow target consuming the paste.** With `SWAR_TEST_SLOW_PASTE_MS`, confirm behavior when the target is slow to accept Cmd+V and Swar has moved on.
- **Held-Option leaking into the paste chord.** Regression-assert the private event source isolates a physically-held modifier from the synthesized Command+V (you fixed this; keep the test).
- **Back-to-back dictations racing the clipboard.** Second session writes the pasteboard while the first's Cmd+V is still in flight. Serialization should prevent overlap — prove it rather than assume it.

### 2.5 SQLite write ↔ history refresh ordering — P1

Flutter refreshes history on the completion event; the write is a transaction.

- Confirm the completion event cannot arrive at Flutter *before* the write commits (else the refresh shows stale data or misses the new row). Force with `SWAR_TEST_SLOW_HISTORY_MS`.
- FTS index update racing a concurrent search query — run a search during the post-dictation FTS write and confirm no partial/corrupt result.

### 2.6 Model load ↔ first keypress / language switch — P1

- Dictation start *during* warm-model preparation at cold start — confirm it queues, blocks cleanly, or fails with a clear state, never a half-loaded context.
- Language switch (e.g., English → explicit Hindi) that triggers a model swap while a keypress arrives — confirm no dictation runs against a context that is mid-swap.

### 2.7 Cancellation at stage boundaries — P1

Cancellation is allowed before post-processing. Fire cancel landing *exactly* at the `recording→finalising` and `transcribing→cleaning` transitions. A cancel that arrives one instruction too late must be either honored or safely dropped — never leave a dangling session or a half-written history row.

### 2.8 Device change mid-session — P1

Unplug the mic, switch Bluetooth route, change sample rate, and revoke mic permission **while recording**. Each is a race between "device gone" and "worker still draining." Confirm the state machine reaches `failed` (not a hung `finalising`), the coordinator releases (§2.3), and no partial buffer is decoded as garbage.

---

## 3. Memory growth

A resident app that leaks even a little per dictation becomes a multi-gigabyte process by end of day. Unit tests never catch this; only soak + trend does.

- **Per-cycle RSS trend.** Run the §1.4 soak harness for 1,000+ cycles and plot peak RSS. A healthy app returns to a flat baseline between dictations. Any monotonic climb is a leak — even a slow one.
- **Whisper context churn.** Confirm the warm context is genuinely reused, not reloaded per session (assert the load counter stays at 1 across many dictations per language). A silent reload-per-dictation both leaks and pins CPU.
- **Audio buffer release + zeroing.** The in-memory PCM must be released *and zeroed* after finalisation — verify on the abnormal-exit path (window closed / quit mid-session), not just the happy path. This is both a memory and a privacy guarantee.
- **FFI boundary leaks.** whisper.cpp allocations freed on every path including error paths and cancellation. Run the soak under ASan/LSan.
- **History/preview event backpressure.** If Flutter is slow to drain lifecycle events, confirm the Rust→Dart event channel does not accumulate unbounded partial-transcript events. Preview emits frequently — a slow UI must not grow a queue.
- **SQLite growth policy.** Confirm history retention actually prunes; a "keep forever" default plus daily use grows the DB indefinitely. Verify FTS index size tracks row deletion.
- **BYOK key lifetime.** The optional API key is held in process memory by design — confirm it is dropped when BYOK is disabled and never migrates to disk/logs.

---

## 4. Battery drain & thermal / CPU pinning

For an always-resident app, idle cost matters as much as active cost. A laptop that runs hot or drains fast with Swar installed gets uninstalled regardless of transcription quality.

- **True idle cost.** With Swar resident and no dictation for 30+ minutes, measure CPU wakeups and energy impact (macOS: `powermetrics`, Activity Monitor "Energy" tab; Windows: equivalent). Target near-zero. Investigate any periodic wakeup — an ambient overlay animation or a polling loop running while idle is a prime suspect.
- **Overlay animation while idle.** The recording waveform has "ambient motion even during quieter moments." Confirm that animation is fully stopped (not just invisible) when idle, and does not repaint off-screen. Continuous repaint of a hidden overlay is a classic silent battery sink.
- **Preview re-decode cost.** The preview currently re-decodes the accumulated snapshot roughly once per second rather than only the new tail. On a long dictation this is quadratic-ish work and a thermal/CPU spike. Measure RTF and CPU during a 2-minute dictation; this is the most likely thermal offender in the current build. Quantify before deciding whether true streaming (handoff §7/§13.2) is worth it.
- **Warm-model memory pressure on battery.** Keeping the Whisper context resident is right for latency but costs idle RAM/energy. Test the battery-saver policy: does it unload after idle, and does the next dictation reload acceptably? (Handoff notes the hardware-tier/idle-timeout policy is unbuilt — this is where its absence shows.)
- **Thread-count sanity.** Assert the worker leaves ≥1 core free and caps ASR threads (≤8 per the current design). Verify under load it never spawns unbounded threads across rapid sessions — a thread leak looks like both a memory and a CPU-pinning bug.
- **Busy-wait audit.** Any `loop { try_read() }` without a park/sleep/condvar on the audio reader or preview loop will pin a core at 100%. Grep for spin loops; confirm each blocks or sleeps when idle. TSan won't catch this — code review and a CPU profile will.

---

## 5. Hangs

A hang is worse than a crash: the app looks alive, accepts the shortcut, and does nothing. Every one of these must have a timeout and a visible recovery, never an indefinite wait.

- **ASR never returns.** Fault-inject a wedged decode. Confirm a bounded timeout moves the session to `failed`, releases the coordinator, and shows the user an error — not an eternal `transcribing` state.
- **Paste never acknowledged.** If Cmd+V is sent but the target never consumes it, confirm Swar still completes (clipboard fallback) rather than blocking the pipeline.
- **Join deadlock.** Preview-worker join (§2.2) or audio-worker join on teardown that never completes because the joined thread is itself blocked. loom the join ordering; add a watchdog.
- **Device-open hang.** Some audio devices block on open. Confirm CPAL device preparation has a timeout so a bad device can't wedge startup or a session.
- **UI ↔ core deadlock.** Flutter awaiting a Rust event that never fires because the core is blocked awaiting the UI. Verify the event contract is one-directional at each stage (the handoff's typed-event design should guarantee this — test it).
- **Main-thread block.** Any native call that must run on the main/UI queue (you hit exactly this with `TSMGetInputSourceProperty`) executed from a worker can hang or trap. Audit remaining main-thread-only macOS/Win32 calls; assert they're dispatched correctly.

**General rule to test for:** every cross-boundary wait (worker join, event await, device open, ASR decode, paste) has an explicit timeout and a defined failure transition. Enumerate them; assert each.

---

## 6. Crash paths

The insertion crash (`dispatch_assert_queue_fail` via off-queue Text Input Services) is the template: transcript already produced, process died during a *privileged native side-effect*. Look for siblings.

- **Every native side-effect off its required queue.** Audit macOS Accessibility, foreground-app lookup, overlay-panel, and menu-bar calls, and the Win32 keyboard-hook / foreground-process / overlay calls, for main-thread/queue requirements. Assert correct dispatch; the crash you already fixed proves this class is real here.
- **whisper.cpp on malformed / truncated input.** Feed empty, sub-frame, all-silence, extremely long, and corrupted-tail audio. Confirm graceful error, not a native abort. (The double-VAD and detect-language regressions you fixed live near here — keep those short-case fixtures.)
- **Model file corrupt/partial at load.** A model that passed SHA-256 at install but is later truncated on disk (disk-full, interrupted OS update) — confirm load fails cleanly and prompts re-download rather than crashing.
- **Panic across the FFI boundary.** A Rust `panic!` unwinding into C/Dart is undefined behavior. Confirm panics are caught at the boundary (`catch_unwind`) and converted to error results. Fault-inject a panic in the pipeline and assert the process survives with an error, not a crash.
- **Disk-full during history write / model download.** Confirm transactional failure and a real error, not a corrupt DB or a crash.
- **Permission revoked between sessions.** Mic or Accessibility permission revoked while resident — next session must fail with guidance, not trap.
- **Crash-recovery leaves clean state.** After any recovered crash, confirm: clipboard not left holding stale dictation unexpectedly, coordinator released, no half-written history row, no orphaned worker thread. The privacy-safe `last_dictation_stage` sentinel should let you reproduce and diagnose without recording user text — keep using it.

---

## 7. Suggested execution order

1. **P0 races first, and specifically the two most damaging:** coordinator-never-releases-on-failure (§2.3) and paste-into-wrong-app-after-focus-change (§2.4). These reach users and are severe (silent dead app; leaked private text).
2. Stand up the ThreadSanitizer lane (§1.3) and run the existing pipeline under it — it will surface §2.1/§2.2 races for free.
3. Build the delay-injection seams (§1.1) and soak harness (§1.4).
4. Run the memory trend (§3) and the preview re-decode CPU/thermal measurement (§4) — the preview snapshot re-decode is the likeliest current thermal offender and is worth quantifying before the streaming decision.
5. Enumerate every cross-boundary wait and assert a timeout + failure transition (§5).
6. Audit remaining native side-effects for queue requirements (§6) — same class as the crash already fixed.
7. Fold the P1/P2 cases into the soak harness so they run continuously rather than once.

---

## 8. Assumptions & limitations

- This plan is written against the architecture described in the 2026-07-18/19 handoff; if the coordinator has since moved to pipelined post-processing, the §2.3 serialization assumptions change and several cases need rewording.
- macOS-specific mechanisms (Core Graphics paste, Text Input Services queue, NSPanel) are named because that's the platform with a confirmed crash history in the build; the Windows equivalents (UI Automation, low-level hook, WS_EX_NOACTIVATE overlay) need the same treatment once the Windows runtime is validated, which the handoff lists as outstanding.
- These are reliability/degradation tests. They complement — do not replace — the accuracy and cross-app insertion validation already tracked in handoff §13.
