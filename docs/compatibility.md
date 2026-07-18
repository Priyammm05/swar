# Swar compatibility policy

Compatibility is a product requirement. A successful build on a current development machine is not enough.

## Supported platforms for V1

### macOS

- macOS 10.15 Catalina and newer
- Intel Macs using x86_64
- Apple Silicon Macs using arm64
- One Universal 2 application containing both architectures
- Native execution on each architecture. Intel support must not depend on Rosetta.

The minimum version may only increase after usage data, dependency constraints, security requirements, and an explicit product decision are documented.

### Windows

- Windows 10 version 1809, build 17763, and newer
- Windows 11
- x64 processors

Windows 7 and Windows 8.1 are not release targets. Windows on ARM is an evaluation target and must not be advertised until Flutter, Rust, model adapters, installers, global shortcuts, overlays, and text insertion all pass on physical ARM64 hardware.

## CPU and model policy

The baseline binary must not require AVX, AVX2, Metal, Apple Neural Engine, or a recent GPU. Hardware capabilities are detected at runtime.

- Older Intel Macs and older Windows PCs default to the Lite model pack.
- Apple Silicon and capable Windows systems may enable larger models and accelerated backends.
- Unsupported acceleration falls back to portable CPU execution instead of preventing launch.
- Streaming partials may be reduced on slow hardware. Final transcription must still work.
- Model manifests declare architecture, memory, disk, and acceleration requirements.

## Native API policy

- Compile against modern SDKs while keeping the documented deployment target.
- Guard every API newer than the minimum OS version at runtime.
- Keep accessibility, keyboard hooks, clipboard insertion, and overlays behind narrow platform interfaces.
- Provide fallback behavior when an optional API is unavailable.
- Do not infer capability from OS version alone when a direct feature check exists.

## Release verification matrix

Every release candidate must cover:

| Platform | Architecture | Minimum | Current | Required checks |
| --- | --- | --- | --- | --- |
| macOS | Intel x86_64 | 10.15 | Latest stable | Launch, permissions, shortcut, overlay, insertion, offline dictation |
| macOS | Apple Silicon arm64 | 11.0 | Latest stable | Launch, permissions, shortcut, overlay, insertion, offline dictation |
| Windows | x64 | Windows 10 1809 | Windows 11 | Install, launch, microphone, shortcut, overlay, UI Automation, insertion |

CI verifies compilation and binary architecture. Minimum-version runtime testing uses maintained physical machines or virtual machines because hosted CI runners generally run recent operating systems.

## Dependency review

Before adding or upgrading Flutter plugins, Rust crates, C or C++ libraries, or native SDK features:

1. Confirm their minimum supported operating system.
2. Confirm x86_64 and arm64 macOS support.
3. Confirm Windows x64 support without a recent CPU instruction requirement.
4. Add runtime fallbacks for optional acceleration.
5. Update and execute the compatibility matrix.

