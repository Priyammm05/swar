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
