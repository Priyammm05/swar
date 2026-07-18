# swar engineering rules

1. Flutter's main isolate must never run inference, audio processing, hashing, or large database work.
2. Raw PCM must not cross into Dart.
3. All heavy operations return asynchronously.
4. The Rust dictation state machine is the source of truth.
5. Every native resource has explicit ownership and cleanup.
6. Every model file must pass SHA-256 verification.
7. Audio is never saved in release builds by default.
8. Logs must never include dictation text, clipboard content, or audio.
9. Every schema change requires a migration and migration test.
10. Every new feature must work with the internet disabled after installation.
11. English, Hindi, and Hinglish tests are mandatory.
12. Intent output must pass the protected-token validator.
13. Overlay windows must not steal focus.
14. Text insertion must have a clipboard fallback.
15. Do not add a new top-level page without product approval.
16. UI pages are limited to Dictation, Insights, General Settings, and System Settings for V1.
17. Prefer narrow native interfaces over large platform-channel objects.
18. Do not introduce Python as an end-user runtime dependency.
19. Pin third-party native revisions and keep licence notices.
20. Every performance change requires before-and-after measurements.
21. macOS release artifacts must be Universal 2 binaries containing both arm64 and x86_64 slices.
22. macOS code must support 10.15 or guard newer APIs with runtime availability checks.
23. Windows code must support Windows 10 version 1809 or guard newer APIs at runtime.
24. Baseline native binaries must not require AVX, AVX2, or Apple Neural Engine support.
25. Hardware acceleration must be selected at runtime and always have a compatible fallback.
26. Compatibility changes require updates to `docs/compatibility.md` and the platform test matrix.

## Writing rules

1. Preserve the user's meaning, language, tone, vocabulary, and level of formality.
2. Cleanup must not make dictation sound like generic AI writing.
3. Do not translate mixed-language speech unless the user explicitly requests translation.
4. Avoid em dashes in generated text by default.
5. Personal writing preferences stay local and user-controlled.
