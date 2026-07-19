# Swar architecture

Swar is an offline-first desktop voice keyboard for macOS and Windows.

## Ownership

- Flutter owns presentation, navigation, and lightweight view state.
- Rust owns the dictation state machine, audio orchestration, storage, models, and background work.
- C and C++ adapters own speech and intent model execution.
- Swift and Win32 modules own privileged operating-system integration.

Flutter communicates with Rust through `flutter_rust_bridge`. Raw audio never crosses this boundary. Rust sends small typed state, transcript, metric, and diagnostics events.

## Writing principle

Swar learns how each person communicates. It improves clarity without replacing their voice. Raw mode transcribes. Clean mode repairs speech artifacts. Intent mode restructures only when the user asks for it. Personalization remains local.

## Dependency direction

Presentation depends on application contracts. Application logic depends on domain abstractions. Infrastructure implements those abstractions. Native and model integrations sit behind narrow interfaces.

## Compatibility boundary

Swar ships as a Universal 2 macOS application with native arm64 and x86_64 code. The macOS deployment target is 10.15. Windows targets the Windows 10 API family and supports version 1809 or newer on x64.

Native integrations detect optional APIs and CPU acceleration at runtime. The baseline path must work without AVX, AVX2, Metal, Apple Neural Engine, or other recent hardware features. Model selection may reduce memory use or disable expensive live features on older hardware, but recording, final transcription, cleanup, and insertion must remain available.

## Implemented dictation order

The runtime is built and verified in this dependency order:

1. **Coordinator and state machine.** Rust owns timestamped `idle`, `recording`, `processing`, `inserting`, `completed`, `cancelled`, and `failed` transitions. A new capture may begin while an earlier session finishes post-processing.
2. **Warm model registry.** One named ASR worker owns and reuses the Whisper context. Final decoding uses beam search; optional previews use the lower-latency greedy path.
3. **Persistent audio engine.** Rust owns the CPAL stream, bounded PCM buffers, levels, device selection, and a 350 ms pre-roll. PCM never enters Dart.
4. **Shortcut gesture reducer.** A deterministic Dart reducer translates hold, double-press lock, release, cancel, and toggle actions into coordinator commands without timing logic in widgets.
5. **Insertion adapters.** Platform paste and clipboard adapters are isolated behind narrow contracts. Clipboard restoration occurs only when Swar still owns the clipboard value.
6. **Coordinator-driven Flutter state.** Flutter renders typed native lifecycle events and keeps presentation state lightweight. Models are warmed according to the local setting.
7. **Optional live preview.** Disabled by default. Preview snapshots remain in Rust, use fast decoding, emit deduplicated partial text, and never enter cleanup, history, or insertion.
8. **Transcript enhancer.** A provider-neutral local interface routes raw, clean, and intent work. Protected numbers, addresses, URLs, and code-like tokens are validated before enhanced text is accepted.
9. **Local personalization.** SQLite stores explicit vocabulary, voice metrics, and opt-in edit learning. Nothing is pre-seeded, uploaded, or learned unless the person enables it.

The pinned model files, licences, provenance, and latest local bake-off are in
[`docs/models.md`](models.md).

Each layer has deterministic unit coverage. The combined system is exercised through the native Flutter-to-Rust bridge and the synthetic desktop-user journey.
