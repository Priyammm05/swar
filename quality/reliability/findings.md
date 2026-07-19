# Swar Reliability & Code-Issue Findings

Companion to [degradation-test-plan.md](degradation-test-plan.md). This is the **issue register** produced by a static reliability audit of `crates/swar_core` (~7,100 lines) against that plan, plus the automated-framework result. Every finding has `file:line` evidence and an adversarial verdict (**CONFIRMED** = traced and holds; **PLAUSIBLE** = real gap, needs a runtime harness to prove the worst outcome).

Fix in priority order. IDs are stable — reference them in commits and regression tests.

## Fix status

- **FIXED (commit 1 — coordinator reservation safety):** R-001, R-002, R-005, R-020, R-028. An RAII `ReservationGuard` now releases the coordinator slot on every exit path (early `?`, error, or panic) via a new infallible `DictationCoordinator::abandon`; the release path recovers a poisoned lock instead of no-oping (R-028); the preview-worker spawn returns `Result` and degrades to no-preview instead of `.expect`-panicking under the `ACTIVE_CAPTURE` guard (R-002). Regression tests: `coordinator::abandon_frees_the_slot_from_any_phase`, `abandon_is_idempotent_and_ignores_unknown_sessions`, `api::dictation::reservation_guard_releases_on_drop_and_holds_when_disarmed`.
- **FIXED (commit 2 — cross-boundary timeouts + FFI safety):** R-003, R-008, R-009, R-011, and the ASR half of R-007. ASR `prepare`/`transcribe`/`preview`/`unload` now use `recv_timeout` watchdogs (120/300/60/30 s), so a wedged whisper.cpp call surfaces a recoverable error instead of hanging the caller and the reserved coordinator (R-003; the coordinator then releases via the commit-1 guard). The ASR worker wraps each decode/load in `catch_unwind`, so a panic can no longer unwind into C or kill the single worker — it drops the context and replies with an error (R-008). The BYOK request uses an agent with connect/read/write timeouts (R-009). The audio worker spawn propagates its error as `Result` instead of `.expect` (R-011). Regression tests: `model_registry::worker_response_times_out_instead_of_blocking_forever`, `worker_response_reports_a_stopped_worker`.
- **FIXED (commit 3 — decode/insertion robustness):** R-026, R-027. `transcribe_with_context` now runs input through `prepared_decode_input`, which rejects empty buffers (returns an empty transcript) and neutralises NaN/Inf plus caps length before the whisper.cpp FFI (R-026). The clipboard-ownership lock recovers from poisoning via a `lock_ownership` helper instead of hard-erroring, so one panic can no longer permanently disable insertion (R-027). Regression test: `model_registry::decode_input_rejects_empty_and_sanitises_non_finite_samples`.
- **STILL OPEN (deferred with reason):**
  - R-004 (wrong-window paste, P0): a correct fix must capture the frontmost app/PID at record start and re-verify it before Cmd+V. `insertion.rs` has no app context and the crate has no objc bindings, so this needs a new native frontmost-PID FFI (NSWorkspace/CGWindow) plumbed through the session, plus real-device testing (compilation is not runtime evidence). Deferred to a dedicated native commit.
  - R-006 (tight-bound preview `join`) and R-014 (audio-worker `join` in `Drop`): `std` has no timed join; both now self-terminate within the ASR watchdog window (≤ preview 60 s) rather than never, but a hard bound needs a detach-on-timeout `exited` flag — follow-up.
  - R-013 (device-open timeout): a clean timeout is blocked by cpal `Stream: !Send` (cannot build the stream on a helper thread and return it); needs platform-aware design — follow-up.
  - R-007 insertion half (paste never acknowledged): addressed alongside R-004 in commit 3.
  - Everything else: R-004, R-010, R-012, R-015..R-030.

## Automated framework baseline (real run, this audit)

`./scripts/run_test_framework.sh fast` → **passed**. `cargo fmt`/`check`/`clippy -D warnings` clean; **42 Rust tests** pass; Flutter boundary check + 3 user-test plans verified; Dart format + `flutter analyze` clean; **29 Flutter unit/widget tests** pass ("All tests passed!").

**Critical caveat:** the passing framework exercises **none** of the defects below. They are timing-, load-, panic-, and FFI-dependent — precisely the classes the plan says unit tests miss. A green `fast` run is not evidence of reliability. The infra in plan §1 (delay injection, ThreadSanitizer, `loom`, soak harness) is required to catch these in CI.

## Cross-cutting root causes (fixing these closes many findings at once)

1. **No RAII release for the coordinator reservation.** The reservation (`recording_session` / `post_processing_sessions`) is released only by an *explicit* trailing call. Any panic or early `?` between reserve and release leaks it → the app silently stops recording forever until relaunch. A `Drop`-based guard closes **R-001, R-005, R-020** and hardens **R-006/R-007**.
2. **`.expect()` on `thread::spawn` while a global mutex guard is held.** Spawn failure (thread/FD exhaustion — a stress condition, not hypothetical) panics *under the guard* and **poisons** the mutex, bricking the whole subsystem. Occurs at three sites: **R-002, R-011**, and the audio worker. Fix: propagate spawn errors as `Result`; never hold the lock across spawn/FFI.
3. **No timeout on any cross-boundary wait.** ASR `recv()`, preview `join()`, native paste, and the BYOK HTTP call all block unbounded. A single wedge hangs the session with the reservation held. Covers **R-003, R-006, R-007, R-009, R-013, R-014**. Fix: bounded wait + `Failed` transition that releases the coordinator, per plan §5.
4. **No `catch_unwind` at the whisper.cpp / native FFI boundary.** A Rust panic unwinding into C is UB; even absent UB, it kills the unsupervised worker permanently (**R-008**). Wrap FFI bodies; supervise/respawn the worker.

---

## P0 — can reach real users, severe (fix first)

### R-001 · Coordinator reservation leaked on panic in `finish_capture` — silent dead app · CONFIRMED
`crates/swar_core/src/api/dictation.rs:283-296` (driving `finish_capture` 299-425)
The `Ok`/`Err` match releases the coordinator, but a **panic** in `finish_capture` (which calls whisper `transcribe` :325, native `insert_with_clipboard` :370, `save_dictation` :392 — all abort/panic-prone) unwinds past `complete_coordinator_session`, leaving `recording_session = Some`. If frb catches the unwind at the boundary the process looks alive but every future `reserve_recording` returns "another dictation session is already recording." **Dictation is dead until relaunch.**
**Fix:** RAII reservation guard (release in `Drop`) or `catch_unwind` around `finish_capture` with a `finally`-style release. (Root cause 1.)

### R-002 · Preview-worker spawn `.expect()` poisons the `ACTIVE_CAPTURE` mutex — kills all dictation · CONFIRMED
`crates/swar_core/src/api/dictation.rs:551` (guard held from :177)
```rust
.expect("the optional preview worker must start")
```
`start_dictation_session` holds the `ACTIVE_CAPTURE` guard across its whole body; `spawn_preview_worker` runs inside it. Under thread/FD exhaustion `spawn` fails, `.expect` panics **while the guard is live** → mutex poisoned → every future `start`/`finish`/`cancel` returns "lock poisoned." Worse than R-001: also leaks the reservation (:193) and never stops the already-started capture stream (:215). Preview is *optional* — panicking on it is indefensible.
**Fix:** degrade to no-preview on spawn failure (return `Err`, never `.expect`); build `ActiveCapture` before taking the lock so the guard isn't held across spawn/FFI. (Root cause 2.)

### R-003 · ASR decode `recv()` has no timeout — one wedged decode hangs the entire ASR subsystem · CONFIRMED
`crates/swar_core/src/asr/model_registry.rs:86-89` (also :64-67, :108-111, :118-121)
```rust
result.recv().map_err(|_| "the ASR worker stopped during transcription".to_owned())?
```
A single worker serializes all commands. If `state.full()` wedges inside whisper.cpp, the caller blocks forever in `Transcribing`, no timeout moves it to `Failed`, and **every future Prepare/Transcribe/Unload** is blocked too. Propagates into `stop_preview`'s `join()` (R-006). Coordinator never releases → silent dead app.
**Fix:** `recv_timeout(bounded)` on all four decode paths → `Failed` on timeout; watchdog + supervised respawn of the ASR worker. (Root cause 3.)

### R-004 · No target re-validation before Cmd+V — private dictation pasted into the wrong window · CONFIRMED
`crates/swar_core/src/insertion.rs:120-213` (`automatic_paste_is_available` only checks global AX permission, :227-235; paste fired blind at :180 after a time delay)
Nothing captures or re-verifies the originally-focused target before posting Cmd+V. If the user Alt-Tabs or focus is stolen during finalisation / the 100 ms settle, `CGEventPost` delivers Cmd+V to whatever is frontmost **now** → private text pasted into a chat box, address bar, or terminal. Plan §2.4, severity S0-class (privacy).
**Fix:** capture target app/PID (or focused `AXUIElement`) at recording start, thread it into insertion, re-verify frontmost immediately before paste; on mismatch fall back to clipboard-only (`copied_fallback`).

---

## P1 — degrades over a session; likely but recoverable

### R-005 · `cancel_capture` error leaves the reservation held · CONFIRMED
`crates/swar_core/src/api/dictation.rs:445-455` — `take_capture` already removed the session; if `capture_engine::cancel_capture` (:449) returns `Err`, the `?` returns before `cancel_recording` (:453). Now `ACTIVE_CAPTURE=None` **and** `recording_session=Some`: can neither start nor recover. **Fix:** release via RAII/`finally`, or move `cancel_recording` ahead of the fallible engine call. (Root cause 1.)

### R-006 · Unbounded preview `worker.join()` hangs finish/cancel, holding the reservation · CONFIRMED
`crates/swar_core/src/api/dictation.rs:554-559` (`stop_preview`) — the preview worker can be mid-`transcribe_preview` (whisper) when joined; the `running` flag is only checked at loop top (:512), so a wedged decode never sees it, and `join()` has no timeout. Blocks finish/cancel forever with the reservation held. **Fix:** bounded join + watchdog; make the preview decode cancellable between chunks. (Root cause 3.)

### R-007 · No timeout on `transcribe`/`insert` on the coordinator-held path · CONFIRMED
`crates/swar_core/src/api/dictation.rs:325, 370` — both run synchronously while the coordinator is reserved. A wedged decode or an unacknowledged paste hangs in `Transcribing`/`Inserting` with the reservation held. **Fix:** per-wait timeout + `Failed` transition that releases the coordinator (fix may partly live in callee crates). (Root cause 3.)

### R-008 · No `catch_unwind` at the whisper FFI boundary; unsupervised worker dies permanently · CONFIRMED (worker death) / PLAUSIBLE (UB-into-C)
`crates/swar_core/src/asr/model_registry.rs:262-264` (decode), `:158-201` (unsupervised `while let Ok(..) = receiver.recv()` loop), `:162` (C→Rust logging callbacks) — a panic in the decode/callback unwinds into whisper.cpp C (UB) and/or kills the worker thread with no respawn → all subsequent ASR returns "worker unavailable" forever. **Fix:** `catch_unwind` per command → `Err`; keep/respawn the worker. (Root cause 4.)

### R-009 · BYOK enhancement HTTP call has no timeout — stalled provider hangs the pipeline · CONFIRMED
`crates/swar_core/src/enhancement.rs:100-104` — `ureq` 2.12.1 (pinned) applies **no** default timeout; `send_json` on a half-open endpoint blocks in `Enhancing` indefinitely with the reservation held. **Fix:** `AgentBuilder` with `timeout_connect`/`timeout_read` so it fails fast to the deterministic fallback (which already exists). BYOK users only. (Root cause 3.)

### R-010 · Cross-language warm-context churn — full model reload on every language switch · CONFIRMED
`crates/swar_core/src/asr/model_registry.rs:203-217, 325-335` — single-slot cache keyed by path; Hindi uses `ggml-hi-small.bin`, others the base model, so alternating languages forces a multi-hundred-MB `WhisperContext::new_with_params` reload each switch → CPU/thermal spike, and the "load count stays at 1" soak assertion fails. **Fix:** bounded LRU (2) of warm contexts keyed by resolved path.

### R-011 · Audio-worker spawn `.expect()` poisons the `AUDIO_ENGINE` lock · CONFIRMED (path) / PLAUSIBLE (trigger)
`crates/swar_core/src/audio/capture_engine.rs:344` — `spawn_worker` runs under the `AUDIO_ENGINE` mutex (`begin_capture`/`prepare`); a spawn failure `.expect`s under the guard → poisons `AUDIO_ENGINE` → all audio calls return "lock poisoned" forever. Same class as R-002. **Fix:** propagate the spawn error as `Result` up through `start`/`begin_capture`. (Root cause 2.)

### R-012 · Continuous mic capture + per-sample mutex while idle — battery/thermal + hot mic · CONFIRMED
`crates/swar_core/src/audio/capture_engine.rs:325-343` — the persistent stream starts at `prepare()` and is **never** paused (no `stream.pause()` anywhere); the worker drains and locks the `accumulator` mutex **once per sample (~16k/s) indefinitely**, even with no active dictation, and the mic stays live. The 4 ms sleep only engages when the ring is momentarily empty. Permanent idle CPU/wakeup/battery cost on an always-resident app (plan §4). **Fix:** pause the stream when no session is armed; batch the worker drain to lock once per pass, not per sample.

### R-013 · Device open/build/play has no timeout and blocks under the global lock · CONFIRMED (no timeout) / PLAUSIBLE (hang)
`crates/swar_core/src/audio/capture_engine.rs:145-169` — `default_input_config`/`build_input_stream`/`play` run synchronously under `AUDIO_ENGINE`. Some devices (Bluetooth/virtual/aggregate) block on open → wedges *every* audio op, app hangs while looking alive. **Fix:** open on a helper thread with a bounded timeout → `Failed`; at minimum prepare the device outside the global lock. (Root cause 3.)

### R-014 · Capture `worker.join()` in `Drop` has no timeout, under the global lock · CONFIRMED (no timeout) / PLAUSIBLE (deadlock)
`crates/swar_core/src/audio/capture_engine.rs:208-210` (Drop from `release()` and device-swap, all under the lock) — the worker runs a caller-supplied `level_callback`; if it ever blocks, the worker never returns and `join()` blocks forever while `Drop` holds `AUDIO_ENGINE`. **Fix:** bounded join + treat a missed deadline as a logged leak; document `level_callback` must be non-blocking. (Root cause 3.)

### R-015 · Captured PCM freed but never zeroed on finish/cancel/abnormal-exit — privacy + memory · CONFIRMED
`crates/swar_core/src/audio/capture_engine.rs:105-119` — `finish` hands out `active.samples` (later dropped) and `cancel` drops it; `Vec<f32>` drop only frees, never overwrites, so up to 300 s of dictation PCM lingers in freed heap. Abnormal exit (window closed mid-recording) frees `active.samples` and the rolling `pre_roll` (~350 ms of always-captured mic audio) without zeroing. Plan §3 calls zeroing both a memory and a **privacy** guarantee. **Fix:** zero `active.samples` on finish (after copy-out), cancel, and in `Drop for ActiveBuffer`; clear `pre_roll` when disarmed. (Tied to R-012.)

### R-016 · `recommended_model_status()` SHA-256 hashes ~190 MB on the UI thread — UI stall · CONFIRMED
`crates/swar_core/src/api/models.rs:37-41, 116-166` — the `#[frb(sync)]` status call eagerly `verified_file`s the VAD and Hindi models (full streaming SHA-256; Hindi is 190 MB). The `&&` only short-circuits when the model is **absent**, i.e. never on the installed happy path Settings actually hits → hundreds of ms to seconds of UI freeze per call. **Fix:** gate the deep hash behind size+mtime, or move the call off `#[frb(sync)]`.

### R-017 · No history/learning retention or pruning — unbounded DB growth · CONFIRMED
`crates/swar_core/src/storage.rs:219-300, 312-342, 518-527` — schema has `is_deleted` but nothing ever sets it; the only delete path is `clear()` (delete-all); `learning_examples` also grows per opted-in edit. Daily use grows `dictations` + FTS + `learning_examples` to multi-GB with nothing bounding it. **Fix:** age/count retention prune (FTS `AFTER DELETE` trigger shrinks the index), cap `learning_examples`, periodic `VACUUM`/WAL checkpoint.

### R-018 · Rust→Dart event stream is unbounded; `AudioLevel` events accumulate under a slow UI · CONFIRMED (unbounded) / PLAUSIBLE (magnitude)
`crates/swar_core/src/api/dictation.rs:220-232` — `StreamSink::add` is backed by an unbounded channel and the result is discarded; `AudioLevel` fires per audio callback for the whole recording with no bound/coalescing. A busy UI thread lets the meter queue climb RSS (plan §3). **Fix:** rate-limit `AudioLevel` to ≤30 Hz / drop-oldest, or shed events when the sink is behind.

### R-019 · Model load at dictation start does not re-verify integrity — truncated model → possible native abort · PLAUSIBLE
`crates/swar_core/src/api/dictation.rs:184-187` — only an existence check before `prepare_for_language`; a model that passed SHA-256 at install but was later truncated (disk-full, interrupted OS update) is handed straight to whisper.cpp. If the load FFI aborts on malformed input, the process crashes (plan §6). **Fix:** cheap size/magic check before load, and ensure the load FFI yields `Err` (not abort) on a bad file → prompt re-download.

### R-020 · `Ok`-branch `?` transitions run before the release call — latent reservation leak · PLAUSIBLE
`crates/swar_core/src/api/dictation.rs:277-282, 286-287` — the `Ok` branch releases only after two fallible `?` transitions; the `Err` branch deliberately uses `let _ =` to avoid exactly this, but the `Ok` branch does not. Unreachable under today's transition table, but a future state-machine change silently reintroduces a leak. **Fix:** RAII release (root cause 1) makes it safe by construction.

---

## P2 — edge hardware / long-tail; validate before broad release

### R-021 · `INSERT OR REPLACE` skips the FTS delete trigger → latent index corruption · PLAUSIBLE (dormant)
`crates/swar_core/src/storage.rs:314-321` — external-content FTS5 with an `AFTER DELETE` trigger, but `PRAGMA recursive_triggers` is never set ON, so REPLACE deletes the row without emitting the FTS `'delete'` → orphaned FTS content. Safe today only because ids are fresh UUIDs (REPLACE never fires) — an accidental guard, a footgun for any future idempotent-save/retry. **Fix:** plain `INSERT`, or `recursive_triggers=ON`, or explicit delete-then-insert.

### R-022 · Disk-full mid-download orphans the `.partial`; no free-space precheck or read timeout · CONFIRMED
`crates/swar_core/src/api/models.rs:87-113` — `write_all` failure `?`-returns before the `remove_file(&partial)` cleanup (which only runs on the integrity-mismatch branch); no free-space precheck before ~380 MB; `ureq::get(..).call()` has no read timeout (stalled connection hangs). Fails cleanly (no corruption) but leaks a partial and can hang. **Fix:** RAII cleanup on every error path, free-space precheck, `ureq` read timeout.

### R-023 · `#[frb(sync)]` functions do blocking DB/disk IO on the UI thread · CONFIRMED
`crates/swar_core/src/api/personalization.rs:20-67`, `settings.rs:61-82` — `list/add/delete_vocabulary`, `record_user_edit`, `get_voice_style_profile`, and `save_settings` (sync `create_dir_all`+`write`+`rename`) run on the Dart UI isolate and contend on the global store mutex held by `save_dictation`. UI stalls behind a DB write / slow volume. **Fix:** move DB/disk-touching calls off `#[frb(sync)]`.

### R-024 · `apply_vocabulary` loads the entire vocabulary table on every dictation · CONFIRMED
`crates/swar_core/src/api/personalization.rs:75-104`, `storage.rs:480-495` (no `LIMIT`), call site `dictation.rs:336` — O(tokens × entries) nested scan on the latency-critical finalize path; `custom_vocabulary` is auto-populated per opted-in edit and uncapped. (History paging itself is fine — it uses `LIMIT/OFFSET`+FTS5.) **Fix:** cap vocab, cache with invalidation, or push replacement into SQL.

### R-025 · BYOK API key not zeroized on drop and derives `Debug` · PLAUSIBLE
`crates/swar_core/src/api/dictation.rs:98-113` — the key is a plain `String` in `DictationSessionConfig` (kept in `ACTIVE_CAPTURE` for the whole session, freed without zeroing) and the struct `derive(Debug)`, so any `{:?}` prints it. It is correctly **not** persisted to disk (`settings.rs` omits it). **Fix:** wrap in `secrecy::Secret`/`Zeroize`, redact from `Debug`, drop right after the enhancement call.

### R-026 · Unvalidated decode input + unbounded, non-coalesced preview channel · CONFIRMED (validation) / PLAUSIBLE (abort)
`crates/swar_core/src/asr/model_registry.rs:262-264, 47, 81/104` — `samples` reaches `state.full()` with no empty/sub-frame/NaN/length guard (final path disables VAD), and the command channel is unbounded with each preview cloning a `Vec<f32>`, so a slow decoder grows memory. Upstream guards empty speech (hence P2). **Fix:** reject empty/sub-frame, sanitize NaN/Inf, cap length, coalesce/bound preview commands.

### R-027 · `CLIPBOARD_OWNERSHIP` mutex poisoning bricks all future insertions · CONFIRMED (behavior)
`crates/swar_core/src/insertion.rs:10, 155-158, 192-205` — every insertion maps a poisoned `CLIPBOARD_OWNERSHIP` lock to a hard error; a panic under the guard permanently disables insertion (transcribes but can never insert). **Fix:** recover from poison (`unwrap_or_else(|e| e.into_inner())`) — the guarded record is small and reconstructible — or use a non-poisoning lock.

### R-028 · Poisoned coordinator lock makes the release path a silent no-op · PLAUSIBLE
`crates/swar_core/src/api/dictation.rs:622-632` — `release_recording_reservation`/`complete_coordinator_session` use `if let Ok(..) = COORDINATOR.lock()`, so a poisoned lock silently skips the release, leaking the reservation. Not reachable today, but silent-skip-on-poison is the wrong default for a release path. **Fix:** recover the poisoned guard and still release.

### R-029 · Tail-audio truncation race in `finish_capture` (no drain barrier after post-roll) · CONFIRMED
`crates/swar_core/src/audio/capture_engine.rs:259-278` — after the 250 ms post-roll sleep, `finish` takes `active.samples` immediately with no barrier that the worker has popped everything from the `rtrb` ring; samples that arrived after the worker's last `pop` are lost (small, non-deterministic tail clip). **Fix:** wait until the ring is empty *and* the worker processed it (a "drained through seq N" signal) before reading.

### R-030 · Overrun policy discards the whole utterance on a single dropped sample · CONFIRMED (policy)
`crates/swar_core/src/audio/capture_engine.rs:268-270` — one dropped sample makes `finish_capture` return "audio buffer overflowed" and reject the entire dictation. Safe (no crash/growth) but harsh; needs a conscious product decision and a test that the drop counter actually fires under a stalled consumer (`SWAR_TEST_STALL_CONSUMER_MS`). **Fix:** tolerance threshold or degrade-not-discard policy.

---

## Verified sound (adversarially checked, no defect)

- **Realtime CPAL callback** is genuinely lock-free / non-allocating / non-blocking (`capture_engine.rs:404-411`); overrun bumps a relaxed atomic. Teardown order is correct — stream dropped before worker join, no callback-after-free (`:204-212`).
- **Single Whisper context is serialized** through one `swar-asr-worker` via `mpsc`; preview is joined before final decode (`dictation.rs:301→557` then `:325`) — no concurrent context access. Same-language dictations reuse the warm context (load count flat; cross-language is R-010).
- **macOS TSM/off-queue paste crash is addressed** — Enigo compiled out on macOS (`insertion.rs:4-8`), raw Core Graphics key codes, private event source isolates held modifiers, 100 ms pasteboard settle, CF objects released on both paths.
- **Completion-vs-commit ordering is safe** — `save_dictation` commits synchronously inside `finish_capture` before the completion event/return reaches Flutter (plan §2.5).
- **History pagination & search are correct** — `LIMIT/OFFSET` + FTS5 `MATCH`, capped at 100, no Dart-side search, no load-all (R-024 vocabulary is the only hot-path load-all).
- **Download integrity core is correct** — `.partial` temp file, hash-while-streaming, SHA-256 verify, atomic rename, delete-corrupt-on-mismatch (gaps are only R-019 load-reverify and R-022 disk-full/timeout).
- **Cancellation legality is correct** — the state machine forbids `Cancelled` from any post-processing state; a legal cancel can't leave a half-written row.
- **UTF-8 boundary safety** in enhancement cleanup holds for Devanagari input (ASCII-anchored slicing).

## Suggested fix order (from plan §7)

1. **R-004** (wrong-window paste) and the RAII fix that closes **R-001/R-005/R-020** — the two most damaging: leaked private text and silent dead app.
2. Timeouts on every cross-boundary wait: **R-003, R-006, R-007, R-009, R-013, R-014**; add **R-008** `catch_unwind` + worker supervision.
3. Kill the spawn-`.expect`-under-guard poisoning: **R-002, R-011** (and audit for a fourth site).
4. Battery/thermal: **R-012** (pause idle stream) and **R-010** (context LRU); quantify the preview re-decode cost (plan §4).
5. Memory/UI: **R-016, R-017, R-018, R-023, R-024**.
6. Then the remaining P2s, and stand up the plan §1 infra (delay injection, TSan, `loom`, soak) so a regression can't silently return.
