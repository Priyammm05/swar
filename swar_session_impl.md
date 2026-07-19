# Swar implementation session record

**Product:** Swar (स्वर), a private offline voice keyboard for macOS and Windows
**Session date:** 2026-07-18 to 2026-07-19
**Document status:** Current engineering handoff based on the checked-out source, Git history, test results, the supplied specifications, and the reference projects shared during the session
**Current repository branch:** `main`
**Current repository version:** `0.1.0`

## 1. Why this document exists

This file records what was designed, implemented, tested, fixed, and left for later during the first substantial Swar build session.

It is deliberately more precise than a conversation summary. Each item is classified as one of the following:

- **Implemented:** present in the checked-out source.
- **Verified:** exercised by an automated test, a build check, or a completed user test.
- **Referenced:** an external project influenced a product or engineering decision, but its code was not copied.
- **Specified:** required by `swar.md` or `swar_addition.md`, but not necessarily implemented.
- **Remaining:** incomplete, unverified, or deliberately deferred.

This distinction matters because several source documents describe the intended final system while the current repository is an early working build.

## 2. Current working result

At the end of this session, the installed macOS build can:

1. Stay resident after its main window is closed.
2. Reopen from the Dock or menu bar.
3. Use Option or Control as the configurable global dictation key.
4. Start recording while the key is held.
5. Lock recording through the double-press gesture.
6. Prevent a new recording while the previous result is still being completed.
7. Capture from the built-in microphone by default, with another microphone selectable in Settings.
8. Transcribe locally with `whisper.cpp` through the Rust core.
9. Route English, Hindi, Hinglish, and Automatic modes without translating the speech.
10. Apply deterministic local cleanup and optional protected enhancement.
11. Paste the final result into the previously focused macOS text field.
12. Keep a clipboard fallback if automatic paste is unavailable.
13. Save local dictation history and update local Insights.
14. Search history, load it in pages of 50, and edit a history item.
15. Store personal vocabulary and optional learning data locally.
16. Run without sending audio to a Swar server.

The final user test in this session confirmed that dictation text was automatically pasted into the Codex text field after the macOS insertion crash was fixed.

## 3. Product decisions established during the session

### 3.1 Local first is the default

Swar is designed to work after installation with the internet disconnected. Audio capture, speech detection, ASR, deterministic cleanup, history, Insights, and personal vocabulary are local.

An optional OpenAI-compatible cleanup provider exists as an explicit opt-in. It is not the default, and its API key is held only in process memory by the current Flutter view model. It is not saved in the repository or settings file.

### 3.2 Flutter stays presentation-focused

Flutter owns:

- the Dictation page;
- the Insights page;
- the General and System Settings dialog;
- navigation;
- lightweight view models;
- rendering small typed lifecycle events;
- the deterministic shortcut gesture reducer.

Flutter does not receive raw PCM and does not execute ASR, audio processing, model hashing, or large SQLite operations.

### 3.3 Rust owns the working pipeline

Rust owns:

- the dictation state machine;
- session coordination;
- persistent audio capture;
- pre-roll and bounded audio buffers;
- resampling and speech-region filtering;
- model installation and SHA-256 verification;
- warm Whisper model ownership;
- transcription;
- deterministic cleanup and enhancement routing;
- protected-token validation;
- clipboard and insertion orchestration;
- SQLite history, search, Insights, vocabulary, and learning data;
- benchmarks and privacy-safe stage diagnostics.

### 3.4 Native code owns privileged desktop behavior

Swift owns macOS modifier-key monitoring, foreground-application lookup, Accessibility prompting, menu-bar integration, window reopening, and non-activating overlay panels.

Win32 code owns the corresponding Windows keyboard hook, foreground-process lookup, and topmost non-activating overlay implementation.

### 3.5 The app should preserve the person, not produce generic AI prose

The current writing contract is:

- Raw mode should preserve the spoken words and only repair spacing.
- Clean mode may remove obvious speech artifacts and apply spoken punctuation.
- Intent mode may restructure only through a guarded enhancement path.
- Mixed English and Hindi must not be translated.
- Numbers, names, URLs, email addresses, code-like values, negation, and language mixture are protected.
- Local vocabulary and writing preferences stay user-controlled.
- Generated product copy should avoid generic AI-startup language and avoid em dashes by default.

The requested Claude authoring layers, `oynix-pitch-writer`, `pitch-psychology`, and `persuasive-copywriting`, were discussed as writing guidance. No corresponding skill packages or runtime code are stored in this repository. Swar’s enforceable writing rules currently live in `AGENTS.md`, `models/prompts/cleanup-v1.txt`, and the Rust cleanup and validation code.

## 4. What was built during this session

### 4.1 Repository and release foundation

- Flutter desktop application for macOS and Windows.
- Rust workspace and `swar_core` crate.
- `flutter_rust_bridge` generated boundary.
- macOS deployment target of 10.15.
- Windows target policy of Windows 10 version 1809 or newer on x64.
- Universal 2 macOS packaging configuration with arm64 and x86_64 slices.
- CI lanes for Flutter, Rust, macOS, and Windows.
- Local model and generated-artifact ignore rules.
- GitHub login and HTTPS API publishing scripts that do not place tokens in source code.
- Capability-sized publishing manifests and descriptive Git commit history.
- Green application icon and template-style menu-bar icon roles.
- Local signing script for stable macOS Accessibility identity during development.

### 4.2 Application shell and visual system

- Two top-level product destinations: Insights and Dictation.
- Settings opens as a dialog rather than becoming another permanent content page.
- General and System sections inside Settings.
- Responsive layouts for dense and compact desktop windows.
- Bundled Manrope variable font, so the application does not depend on a web font.
- Shared neutral, teal, border, spacing, and typography tokens.
- Insights opens as the first view.
- Dictation contains the local activity feed and summary cards.
- Insights contains WPM, total words, correction/activity information, app categories, and streak visualization.

The UI was translated from the screenshots and HTML supplied in the conversation. Wispr Flow was a visual and interaction benchmark. No Wispr source code was available or copied.

### 4.3 Dictation history and Insights

- SQLite-backed history instead of placeholder rows.
- Full-text search through SQLite FTS.
- First page size of 50 rows.
- “Show more activity” appears only when `loaded rows < total rows`.
- Each additional request loads the next 50 or the remaining smaller set.
- No terminal “load more” control after all activity is loaded.
- History refreshes after a completed dictation.
- Blank-audio sentinels are filtered from history and Insights.
- Local correction dialog updates `final_text` and word count.
- Optional learning records a corrected item only when the person opted in.
- Local WPM, total words, dictation count, current streak, and longest streak are calculated from SQLite data.

Not yet implemented in the current Dictation UI: copy, reinsert, and delete actions for individual rows.

### 4.4 Desktop shortcut behavior

The intended interaction was based on the demonstrated Wispr behavior, but Option was selected because Fn was already occupied by Wispr Flow on the test machine.

Current behavior:

- Hold Option or Control to record.
- Release to finish.
- Double press to latch hands-free recording.
- Press again to finish a latched recording.
- Cancel and stop actions travel through the same activation controller.
- Key events received during final transcription and insertion are discarded.
- A new session does not begin until the prior session completes.

The shortcut timing logic lives in a deterministic Dart reducer rather than in a Flutter widget. macOS and Windows only report native key events.

### 4.5 Native overlay

macOS has a native non-activating `NSPanel`; Windows has a topmost `WS_EX_NOACTIVATE` overlay window.

Current states include:

- idle rail;
- hover control with microphone and shortcut label;
- preparing/finalising dotted animation;
- recording waveform with ambient motion even during quieter moments;
- cancel and confirm controls;
- latched recording state;
- a macOS long-press full-screen command overlay experiment.

The overlay is native because it must remain responsive, stay above other applications, and never steal text-field focus while Flutter and Rust perform other work.

### 4.6 Audio engine

The Rust audio engine uses CPAL for CoreAudio and WASAPI input.

Implemented details:

- persistent input stream prepared before the first dictation;
- lock-free `rtrb` ring buffer between the realtime callback and worker;
- 350 ms pre-roll;
- 250 ms post-roll;
- bounded active recording buffer;
- maximum dictation duration guard;
- downmixing to mono;
- native audio-level calculation at 20 windows per second;
- dropped-sample and stream-error counters;
- built-in microphone preference before the system default;
- explicit device selection from Settings;
- no raw PCM crossing into Dart;
- no audio file saved by the release pipeline.

### 4.7 Offline model installation

The model installer downloads to an app-support directory, writes a partial file, hashes the bytes while downloading, verifies the expected SHA-256, and only then atomically replaces the destination.

Current installed pack:

| Role | File | Approximate size | Route |
| --- | --- | ---: | --- |
| Multilingual ASR | `ggml-small-q5_1.bin` | 190 MB | Automatic, English, Hinglish |
| Hindi ASR | `ggml-hi-small.bin` | 190 MB | Explicit Hindi |
| Silero VAD | `ggml-silero-v6.2.0.bin` | 0.9 MB | Preview speech segmentation |

All three files must be present and valid before the recommended pack reports itself installed.

### 4.8 ASR and language routing

The current ASR engine is `whisper.cpp` through `whisper-rs`.

- One named Rust worker owns and reuses the loaded Whisper context.
- Final transcription uses beam search with beam size 5.
- Preview transcription uses greedy decoding.
- English sets Whisper language `en`.
- Hindi sets language `hi` and routes to the Hindi-specific model when installed.
- Hinglish leaves the language unset and supplies a Roman-script context prompt.
- Automatic leaves the language and prompt unset so Whisper chooses from the speech.
- Translation is disabled.
- The worker leaves at least one CPU core for the desktop and uses at most eight ASR threads.
- Whisper’s decoded-token stderr logging hooks are disabled so logs cannot contain dictation text.

Two important ASR defects were fixed:

1. `detect_language=true` in whisper.cpp is a detection-only operation. It returns after language detection instead of continuing normal decoding. Swar now leaves the language null with `detect_language=false` for Automatic and Hinglish. Whisper then auto-detects and continues transcription.
2. Final audio had already passed Swar’s conservative speech gate. Running Silero VAD again inside final Whisper decoding could discard short valid speech. Final decoding no longer applies a second VAD pass. Preview decoding still uses VAD.

### 4.9 Live preview

The current preview worker takes a bounded Rust-side audio snapshot approximately once per second, resamples it, performs a greedy Whisper preview, deduplicates the result, and sends only the partial text event to Flutter.

This is a working local preview, but it is not a true incremental decoder that processes only the new audio tail. Each preview can decode the accumulated snapshot again. True streaming remains a performance improvement.

### 4.10 Cleanup, intent safety, and optional providers

The deterministic cleanup layer currently supports:

- whitespace normalization;
- spoken comma, period, question mark, and line-break commands;
- conservative removal of `um`, `uh`, `erm`, and `hmm`;
- sentence capitalization;
- preservation of Hindi and Hinglish text.

The enhancement router detects intent mode, correction phrases, long or multi-clause input, list cues, and explicit formatting requests.

The built-in `EmbeddedLocalEnhancer` is currently a deterministic editor. Despite its name, it is not an embedded llama.cpp model. It resolves a limited set of clear self-corrections and applies a small amount of app-aware punctuation.

The optional BYOK path can call an OpenAI-compatible `/chat/completions` endpoint only when explicitly selected. It allows HTTPS endpoints and localhost. The result must pass the protected-token and language validator. A rejected result falls back to deterministic text with `swar-INTENT-004`.

The following are specified but not yet built:

- embedded llama.cpp runtime;
- a downloadable 1.7B or 3B cleanup model;
- the 1.7B versus 3B benchmark decision;
- LoRA training and packaging;
- a mature intent model that consistently turns spoken instructions into high-quality structured output.

### 4.11 Local personalization

Implemented:

- explicit spoken-to-written vocabulary entries;
- vocabulary application before cleanup;
- opt-in correction learning;
- local learning examples containing raw, model, and corrected text;
- local voice-style metrics such as average length, contractions, and lowercase starts;
- local JSONL export from Settings;
- no pre-seeded personal profile;
- no automatic upload.

This is the foundation for local adaptation. It is not yet a trained per-user model. Current learning influences exact vocabulary replacements and stores examples for future tuning.

### 4.12 Privacy and diagnostics

- Model, audio, storage, and insertion work stay local by default.
- Release logs do not include transcript text, clipboard text, or audio.
- Developer-service environment variables are removed before synthetic desktop tests.
- User testing session notes are Git-ignored.
- Models, generated reports, crash dumps, and local audio fixtures are Git-ignored.
- A local `last_dictation_stage` file records only a static pipeline label such as `capture`, `transcription`, or `insertion`.
- The static stage made it possible to diagnose the insertion crash without recording the user’s text.

## 5. Current architecture

### 5.1 Ownership map

```text
Flutter UI
  pages, dialog, view models, gesture reducer
        |
        | small typed calls and events
        v
flutter_rust_bridge
        |
        v
Rust core
  coordinator -> audio -> speech gate -> ASR -> cleanup/enhancement
  -> protected validator -> insertion -> SQLite history/metrics
        |
        +--------------------+
        |                    |
        v                    v
whisper.cpp / C++       Native desktop adapters
local ASR               Swift / Win32 shortcuts, overlay, focus, permissions
```

### 5.2 Flutter dependency direction

```text
presentation -> application/domain contracts -> data adapters -> Rust/native bridge
```

Pages depend on repository or gateway interfaces. Production adapters implement those interfaces through Rust or native platform channels. Tests can supply deterministic in-memory fakes.

### 5.3 Startup flow

1. Flutter initializes the Rust library.
2. Rust initializes the local SQLite store and migrations.
3. Flutter loads Rust-backed settings.
4. Flutter creates history, Insights, settings, personalization, and dictation view models.
5. The selected Whisper model is prepared when available.
6. CPAL prepares the selected microphone so pre-roll exists before the first key press.
7. The native runner registers Option or Control monitoring.
8. Flutter synchronizes the idle overlay.
9. The app remains resident when the main window closes.

### 5.4 Start-recording flow

```text
Option/Control down
  -> Swift NSEvent monitor or Win32 low-level keyboard hook
  -> Flutter method channel event
  -> DictationActivationController
  -> ShortcutGestureMachine
  -> DictationSessionViewModel.start
  -> Rust start_dictation_session
  -> reserve coordinator
  -> prepare language-specific model
  -> begin native capture with pre-roll
  -> emit recording and audio-level events
  -> animate native overlay
```

### 5.5 Finish flow

```text
shortcut release or confirm
  -> lock activation controller in completing state
  -> Rust finalising state
  -> stop and join preview worker
  -> drain native capture
  -> downmix/resample to mono 16 kHz
  -> conservative speech-region gate with edge padding
  -> final Whisper beam-search transcription
  -> personal vocabulary
  -> deterministic cleanup
  -> optional routed enhancement
  -> protected-token validator
  -> macOS Command+V or platform fallback
  -> SQLite history transaction and Insights data
  -> completion event
  -> Flutter history refresh
  -> overlay returns to idle
  -> next recording becomes available
```

### 5.6 State machine

Current states:

```text
idle -> preparing -> recording -> finalising -> transcribing -> cleaning
     -> optional enhancing -> inserting -> optional copied fallback
     -> completed -> idle
```

Cancellation is allowed before post-processing. Any stage may move to `failed` where the state machine permits it.

The reconciled specification says a new recording may begin while a previous session is cleaning or inserting. The current implementation does not do that. It deliberately reserves the coordinator until insertion and history finish. This was chosen during debugging so output cannot overlap or reorder. True ordered pipelining remains future work.

## 6. The macOS insertion failure and final fix

### 6.1 User-visible failure

Transcription appeared in local history but not in the active Codex text field. A later build crashed immediately after finishing dictation.

The privacy-safe diagnostic stage showed `insertion`, and macOS produced this relevant crash path:

```text
dispatch_assert_queue_fail
TSMGetInputSourceProperty
enigo::platform::macos_impl::keycode_to_string
enigo::platform::macos_impl::get_layoutdependent_keycode
Enigo as Keyboard::key
swar_core::insertion::SystemPaste::paste
```

### 6.2 Root cause

The crashing build allowed Enigo’s layout-dependent `Key::Unicode('v')` path on macOS. Enigo asked macOS Text Input Services for keyboard-layout information from a Rust worker queue. That API asserts its required dispatch queue and intentionally traps when called from the wrong queue.

This was not an ASR crash. The transcript had already been produced. The process died while trying to generate Command+V.

The earlier Accessibility `AXSelectedText` direct-write experiment also had a reliability problem. Some Electron text fields could report success without changing their contents. That produced a false-positive insertion result and prevented the proven clipboard path from running.

### 6.3 Fix

The current source makes the unsafe path impossible on macOS:

1. Enigo keyboard imports are compiled only on non-macOS targets.
2. macOS automatic paste uses raw Core Graphics virtual key codes.
3. The event sequence is Command down, V down, V up, Command up.
4. V events carry the Command flag.
5. Events use a private event source so a physically held Option key cannot leak into the paste chord.
6. Events are posted to the HID event tap with small spacing.
7. Swar waits 100 ms after publishing the pasteboard value before sending Command+V.
8. The unreliable macOS AX direct-write optimization was removed.
9. macOS keeps the dictated text on the clipboard as a reliable fallback instead of restoring the old value too early.
10. A regression test asserts the exact layout-independent key sequence.

### 6.4 Verification

- Crash-specific insertion regression passed.
- All 41 Rust tests passed.
- Flutter analysis passed.
- All 29 Flutter unit and widget tests passed.
- The corrected release bundle built at 78.9 MB.
- The complete app signature verified on disk.
- The installed app remained running.
- No new macOS crash report appeared after launch.
- The user confirmed automatic paste worked in the Codex field.

### 6.5 Remaining insertion tradeoff

macOS clipboard restoration is currently disabled after dictation. Reliability is preferred over restoring the old clipboard before an asynchronous target consumes the paste. A future implementation should acknowledge successful delivery per target application before safely restoring the previous clipboard.

## 7. Testing and benchmark framework

### 7.1 Fast framework

`./scripts/run_test_framework.sh fast` runs:

- Rust formatting check;
- Cargo check;
- Clippy with warnings denied;
- all Rust tests;
- Flutter boundary verification;
- user-testing manifest verification;
- Dart formatting check;
- Flutter analysis;
- Flutter unit and widget tests.

The post-crash-fix fast run passed with 41 Rust tests and 29 Flutter tests.

### 7.2 Full framework

`./scripts/run_test_framework.sh full` additionally runs:

- local text-pipeline microbenchmark;
- six real-model ASR benchmark fixtures on macOS;
- native Flutter-to-Rust bridge test;
- synthetic desktop-user journey;
- screenshot and JSON evidence generation.

The full framework passed earlier in the session before the final insertion crash fix. The insertion fix then passed the fast framework and the real user paste test. A fresh full run on the final source is still required before release sign-off.

### 7.3 Current ASR fixtures

- long English;
- long Hindi;
- long Hinglish;
- short Automatic English;
- short Automatic Hindi;
- short Hinglish.

The short cases protect against the detect-language and double-VAD regressions discovered during this session.

### 7.4 Individual-user framework

The repository includes:

- Phase 0 foundation scenarios;
- Phase 1 shell scenarios;
- Phase 2 dictation scenarios;
- stable task IDs;
- private local session templates;
- severity classification;
- release gates for automation, privacy, platform behavior, and human validation.

The testing model is intentionally layered. Unit tests prove deterministic rules. Synthetic users prove complete scripted journeys. Human testing catches confusing states, trust problems, visual friction, perceived latency, and whether the result still sounds natural.

## 8. External projects and references shared in the session

### 8.1 Attribution rule for this build

No source file in the Swar repository is copied from the projects below, and the repository contains no upstream code attribution markers from them. They were studied or discussed as product and architecture references. Swar’s implementation was written for its Flutter, Rust, Swift, and Win32 architecture.

This matters because several references use GPL or AGPL licenses. Copying their code would require a separate licensing decision. Studying their public behavior and independently implementing a design does not make their source part of Swar.

### 8.2 Reference map

| Reference | What it was useful for | Relationship to current Swar |
| --- | --- | --- |
| [FluidVoice](https://github.com/altic-dev/FluidVoice) | Native macOS local-first dictation, multiple local models, optional providers, live preview, menu-bar and overlay behavior | Evaluated as a strong local-first product reference. Swar independently implements local ASR, optional BYOK cleanup, native overlay, and menu-bar behavior. No code copied. |
| [Handy](https://github.com/cjpais/Handy) | Best architecture reference: lightweight frontend with Rust owning audio, system integration, and ML; CPAL, VAD, resampling, shortcuts, cross-platform packaging | Strong conceptual validation for the user’s decision that Flutter should remain light while Rust owns the core. Swar uses Flutter instead of React/Tauri and implements its own Rust boundaries. No code copied. |
| [Handy architecture writeup](https://openapps.pro/apps/handy) | High-level explanation of Handy’s offline pipeline and architecture | Secondary reading companion to the Handy repository. Not a code source. |
| [drajb/whisper-local](https://github.com/drajb/whisper-local) | Pre-roll, warm model, global push-to-talk, floating level overlay, streaming preview, deterministic spoken formatting, fallback output | Direct design reference for the 350 ms pre-roll, warm model experience, ambient overlay, and user-visible fallback principle. Swar implementation is independent. |
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | Native macOS shortcut, app-aware behavior, personal dictionary, local Whisper, text insertion and native dependencies | Reference for macOS-native interaction and the need for multiple insertion strategies. Swar does not use VoiceInk’s Swift code or dependencies. |
| [FreeFlow](https://github.com/zachlatta/freeflow) | Hold and toggle shortcut behavior, context-aware cleanup, custom vocabulary, OpenAI-compatible providers, selected-text edit concepts | Reference for shortcut semantics, context plus vocabulary constraints, and optional provider shape. Swar’s BYOK provider and reducer were implemented independently. |
| [Voicetypr](https://github.com/moinulmoin/voicetypr) | Second Rust cross-platform desktop example with local Whisper, CPU fallback, model choice, macOS and Windows support | Architecture comparison. Swar uses Flutter plus Rust rather than Tauri plus React. No code copied. |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr) | Broad cross-platform local/cloud model choice, Whisper and Parakeet, BYOK, automatic paste, larger product scope | Product and capability comparison. Swar deliberately keeps V1 narrower and avoids Electron. No code copied. |
| [Gagancreates/whispr-local](https://github.com/Gagancreates/whispr-local) | Minimal Windows hold-to-record, small overlay, local Whisper, cursor injection | Useful as a simple cautionary prototype. Swar does not use its Python runtime because Python is prohibited as a shipped dependency. |
| [fsouza-dot/OpenWhisper](https://github.com/fsouza-dot/OpenWhisper) | Cross-platform push-to-talk, local or Groq option, in-memory audio, credential storage, tray behavior | Reference for privacy and fallback expectations. Swar does not use its Python or faster-whisper runtime. |
| [whisper-writer](https://github.com/savbell/whisper-writer) | Older small Python dictation app, configurable transcription and typing, limited testing and packaging notes | Treated as a cautionary example for maintainability, test coverage, and runtime packaging. The supplied note called it abandoned, but the upstream page does not explicitly declare abandonment. Its latest visible release is from 2024, so it should be described as older or low-activity unless maintainers state otherwise. |
| [awesome-voice-typing](https://github.com/primaprashant/awesome-voice-typing) | Curated catalogue of local, hybrid, desktop, mobile, and terminal voice-typing tools | Discovery and comparison list only. No implementation was taken from the catalogue. |

### 8.3 Wispr Flow reference

Wispr Flow was the main interaction and visual benchmark supplied through screenshots and direct testing. It influenced:

- compact idle rail;
- hover microphone control and shortcut label;
- hold and hands-free shortcut behavior;
- waveform proportions;
- finalising dots and loader feedback;
- cancel and confirm button proportions;
- bottom-center placement;
- dense Insights layout;
- Dictation activity layout;
- settings dialog structure;
- expectation that insertion occurs immediately in the active field.

Wispr Flow is not open-source code in this repository. Swar reproduces selected interaction principles with its own native implementation and its own product identity.

## 9. Implementation order 1 to 9 and current status

This table reconciles the nine-item architecture order discussed in the session with what the source actually does today.

| Order | Area | Current status | Remaining |
| ---: | --- | --- | --- |
| 1 | Coordinator and state machine | Implemented and unit-tested. Rust owns typed transitions and holds the session until insertion/history complete. | The specification’s concurrent post-processing pipeline is not implemented. |
| 2 | Warm model registry | Implemented. A dedicated worker reuses one Whisper context and switches by language/model path. | Hardware-tier memory policy, mmap proof, idle timeout, and multiple warm model scheduling remain. |
| 3 | Persistent audio engine | Implemented with CPAL, `rtrb`, pre-roll, bounded buffers, built-in microphone preference, and level events. | Physical Windows, Intel Mac, Catalina, and device hot-plug validation remain. |
| 4 | Shortcut gesture reducer | Implemented and tested for hold, release, double press, toggle, cancel, and completion lock. | Broader physical-keyboard and accessibility testing remains. |
| 5 | Insertion adapters | macOS clipboard plus raw Command+V now works in the user’s Codex test. Windows has a current insertion implementation and clipboard fallback. | Windows UI Automation, full cross-app matrix, paste acknowledgement, undo semantics, and safe macOS clipboard restoration remain. |
| 6 | Coordinator-driven Flutter state | Implemented through typed Rust events and lightweight view models. | Continue reducing duplicated state and verify every failure/recovery UI. |
| 7 | Optional live preview | Implemented as periodic local snapshot decoding with deduplication. | True streaming tail decoding and performance measurement remain. |
| 8 | Transcript enhancer | Router, prompt artifact, deterministic local enhancer, BYOK adapter, and validator are implemented. | Embedded llama.cpp model and its model-quality gates remain. |
| 9 | Local personalization | Vocabulary, correction learning, style metrics, JSONL export, settings, and tests are implemented. | Trained per-user adaptation, richer rhythm/formality features, and LoRA workflow remain. |

## 10. Build-plan phase status

| Phase | Status at end of session |
| --- | --- |
| Phase 0: repository and proof of architecture | Complete for the current milestone. |
| Phase 1: desktop shell | Implemented and tested on the development Mac. |
| Phase 2: local history and Insights | Core implementation complete. Some full-history actions remain. |
| Phase 3: audio capture | Implemented. Broader hardware verification remains. |
| Phase 4: offline ASR | Implemented with multilingual and Hindi model routing. Human accuracy gates remain. |
| Phase 5: global shortcut | Implemented on macOS and in Windows source. Windows runtime proof remains. |
| Phase 6: floating bar | Implemented on macOS and Windows source. More user polish and Windows proof remain. |
| Phase 7: text insertion | Working on the tested Mac. Full app and Windows matrix remains. |
| Phase 8: full dictation history | Paging, search, correction, and refresh are present. Copy, reinsert, delete, and richer details remain. |
| Phase 9: Clean mode | Deterministic core implemented and tested. Golden human-quality set must expand. |
| Phase 10: local Intent mode | Partial. Safe routing and fallback exist; embedded local LLM does not. |
| Phase 10.5: flywheel and LoRA | Data capture and export foundation exists. Training and model runtime do not. |
| Phase 11: India model bake-off | Initial synthetic English, Hindi, and Hinglish model measurements exist. Diverse real-speaker evaluation is incomplete. |
| Phase 12: release engineering | Universal 2 build configuration and local signing exist. Notarization, installers, update system, and full platform release evidence remain. |

## 11. Current model quality evidence

The checked-in model report records the following stable synthetic-speech measurements:

| Model and route | WER | RTF | Current decision |
| --- | ---: | ---: | --- |
| Whisper small q5_1, English | 13.2% | 0.08 | Keep as Balanced candidate |
| Whisper small q5_1, Hinglish | 17.4% | 0.31 | Keep as Balanced candidate |
| Whisper small q5_1, Hindi | 57.1% | 0.37 | Reject as explicit Hindi route |
| Ukta Hindi small q5_1, Hindi | 42.9% | 0.32 | Better fallback, still not release-quality proof |
| Whisper large-v3-turbo q5_0, Hindi | 50.0% | 1.21 | Reject on this gate |

These numbers are regression evidence, not a claim of production accuracy. Hindi and Hinglish still require diverse human speakers, Indian accents, noise, real microphones, technical names, numbers, and code-switch evaluation.

## 12. Git and publication record

The session produced small descriptive commits rather than only “Phase 0” or “Phase 1” labels. The major published milestones were:

1. Initialize repository and desktop foundation.
2. Publish the responsive desktop shell.
3. Add verified local model management and native desktop activation.
4. Connect daily dictation from the shell.
5. Add Wispr comparison benchmarks and diagnosable user tests.
6. Improve offline transcription and insertion.
7. Connect real history and Option-key activation.
8. Build the responsive Insights visual system.
9. Add the compact native overlay and desktop controls.
10. Document compatibility and capability-sized publishing.
11. Build the Rust coordinator and warm audio pipeline.
12. Add protected enhancement and local personalization.
13. Drive Flutter from typed native lifecycle events.
14. Add gesture, lifecycle, history, and settings regressions.
15. Add the full benchmark and synthetic-user framework.
16. Improve multilingual routing and speech filtering.
17. Harden cleanup and insertion privacy.
18. Connect local preferences and personalization UI.
19. Polish native controls and app reopening.
20. Load history in pages of 50.
21. Add reproducible multilingual model benchmarks.
22. Extend offline desktop user journeys.
23. Improve macOS text-field pasting.

At the time this document was created, the final crash fix, short-speech ASR regressions, expanded tests, Phase 2 scenario, and this document were still uncommitted working-tree changes. They should be reviewed and committed in small capability-based groups only after the user authorizes publication.

## 13. What remains before calling V1 complete

### 13.1 Release-blocking product validation

- Run the full framework again on the final insertion source.
- Complete real-speaker English, Hindi, and Hinglish benchmark sets.
- Verify short, long, noisy, accented, technical, number-heavy, and code-switched speech.
- Test insertion in Safari/Chrome, TextEdit/Notes, Codex/Cursor/VS Code, Slack, Mail, Microsoft Office, and password or secure fields.
- Verify undo behavior per application.
- Verify permission denial, later approval, revocation, reinstall, update, and stable-signing behavior.
- Verify microphone disconnect and switching while the app is resident.
- Complete real Windows 10/11 x64 build, shortcut, overlay, microphone, transcription, insertion, and relaunch tests.
- Complete physical Intel Mac and minimum supported macOS testing.
- Retain sanitized synthetic and human evidence for the release candidate.

### 13.2 Core engineering gaps

- Replace preview snapshot re-decoding with true incremental streaming if benchmarks justify it.
- Decide whether ordered concurrent recording/post-processing is worth the complexity.
- Add insertion delivery acknowledgement and safe clipboard restoration.
- Implement or formally defer macOS direct Accessibility insertion per target app.
- Replace the Windows generic text injection path with verified UI Automation where appropriate.
- Add explicit handling for secure fields and excluded applications.
- Add hardware-tier model and memory policies.
- Prove optional acceleration and portable CPU fallback on the full matrix.
- Add model update, rollback, and corrupted-pack recovery flows.

### 13.3 Cleanup and personalization gaps

- Embed llama.cpp only after license, provenance, quality, RAM, and latency gates pass.
- Benchmark a 1.7B model against a 3B model.
- Build correction, restraint, hallucination, entity, number, negation, and language-preservation golden suites from real speech.
- Add richer local vocabulary discovery without silently rewriting words.
- Design the opt-in LoRA workflow and threat model.
- Improve sentence rhythm, formality, spelling preference, and app-register learning locally.
- Decide whether BYOK remains in V1 or moves behind an advanced setting.

### 13.4 UI and lifecycle gaps

- Continue overlay animation and hit-target polish with real users.
- Confirm every native overlay button and long-press path on macOS and Windows.
- Ensure all System Settings switches have real native effects. Some current settings are persisted UI state but are not fully connected to launch-at-login, Dock visibility, audio muting, sounds, or notifications.
- Add copy, reinsert, delete, and detailed history actions.
- Verify Insights categories are based on real per-app data before presenting them as factual usage breakdowns.
- Add a complete onboarding and permission-health flow.
- Add a clear model download, progress, failure, resume, and disk-space experience.

### 13.5 Release engineering gaps

- Production Developer ID signing and notarization.
- Signed Windows installer and SmartScreen reputation plan.
- Auto-update design with signed manifests and rollback.
- Software bill of materials and third-party license notices.
- Reproducible release process and artifact retention.
- Crash collection strategy that never includes dictated content.
- Minimum-OS and older-hardware release matrix sign-off.

## 14. Recommended next sequence

1. Preserve the now-working macOS insertion path with a complete full-framework run.
2. Commit the crash fix and its regression independently from ASR and documentation changes.
3. Run a small manual cross-app paste matrix on the current Mac.
4. Record real English, Hindi, and Hinglish benchmark results without committing personal audio.
5. Stabilize Hindi and Hinglish ASR before adding a cleanup LLM.
6. Validate the Windows build and native interaction loop.
7. Finish history actions and connect every visible System setting.
8. Perform the 1.7B versus 3B cleanup bake-off.
9. Only then choose an embedded local cleanup model and begin LoRA experiments.
10. Complete signing, notarization, installers, update safety, and minimum-platform validation.

## 15. Source-of-truth files

- `AGENTS.md`: enforceable engineering and writing rules.
- `swar.md`: original comprehensive build plan, intentionally Git-ignored.
- `swar_addition.md`: reconciled India-first engine and cleanup decisions.
- `docs/architecture.md`: concise current architecture description.
- `docs/compatibility.md`: platform and hardware evidence policy.
- `docs/models.md`: model hashes, licenses, provenance, and current bake-off.
- `crates/swar_core/src/api/dictation.rs`: end-to-end native dictation orchestration.
- `crates/swar_core/src/audio/capture_engine.rs`: persistent microphone engine.
- `crates/swar_core/src/asr/model_registry.rs`: warm Whisper worker and language routing.
- `crates/swar_core/src/enhancement.rs`: enhancement routing and validator.
- `crates/swar_core/src/insertion.rs`: clipboard ownership and platform insertion.
- `crates/swar_core/src/storage.rs`: SQLite schema, history, Insights, vocabulary, and learning.
- `apps/swar_desktop/lib/app/swar_app.dart`: Flutter application composition and overlay synchronization.
- `apps/swar_desktop/macos/Runner/MainFlutterWindow.swift`: macOS shortcut, permission, focus, and overlay behavior.
- `apps/swar_desktop/windows/runner/flutter_window.cpp`: Windows shortcut, focus, and overlay behavior.
- `scripts/run_test_framework.sh`: fast and full automated quality entry point.
- `quality/user-testing/`: synthetic and human user-validation system.

## 16. Final status statement

Swar is now a working macOS offline dictation prototype with a real Rust-owned audio and transcription pipeline, local data, compact native interaction, multilingual routes, guarded cleanup, and verified automatic paste into the tested Codex text field.

It is not yet a finished V1 release. The most important remaining work is real multilingual accuracy, cross-application insertion proof, Windows and older-Mac runtime validation, full release engineering, and the embedded local cleanup model. The architecture is intentionally prepared for those additions without moving inference or raw audio into Flutter.
