# Phase 0 foundation

This plan validates the first real desktop shell. It checks what a person can observe. It does not ask the tester to inspect source code or developer logs.

## Automation map

The synthetic-user journey covers `PH0-001`, the Flutter portion of `PH0-003`, and lifecycle recovery from `PH0-005`. It also captures normal and compact screenshots. Native macOS menu bar behavior in `PH0-002`, network isolation in `PH0-004`, and subjective observations still require separate evidence.

## Preconditions

- Install a release build, not a debug build.
- Disconnect from the network after installation.
- Record the operating system version, processor, memory, display scaling, and appearance mode.
- On macOS, run once in light appearance and once in dark appearance.

## Task PH0-001: Recognize and open Swar

Start from the installed application without developer guidance. Open Swar and identify what the application is.

### Success criteria

- The green Swar identity is recognizable in the Dock or Windows taskbar.
- The app opens without an unexplained warning or blank window.
- The first screen explains its current purpose in plain language.

### Observe

- Any hesitation before opening the correct item.
- Whether the icon remains legible at small sizes and common display scaling.
- Whether startup feels stalled even when it technically succeeds.

## Task PH0-002: Use the macOS menu bar item

On macOS, find Swar in the menu bar without being told its exact position. Close the main window, reopen it from the menu bar, and then quit Swar.

### Success criteria

- The mark is visible in both light and dark appearances.
- Closing the window does not make Swar feel lost or broken.
- Open and Quit behave as their labels promise.
- Keyboard and VoiceOver users can identify the item as Swar.

### Observe

- Whether the mark is too wide, too small, or visually unclear.
- Whether closing the window is mistaken for quitting.
- Any unexpected focus or window-order behavior when reopening.

## Task PH0-003: Check the native core

Use the visible diagnostics action to check the native core. Describe what the result means without referring to implementation documentation.

### Success criteria

- The action produces a clear success or failure state.
- Streamed events appear without freezing the window.
- Failure remains understandable and recoverable.

### Observe

- Whether the wording explains the result to a non-developer.
- Whether repeated checks produce confusing duplicate state.
- Whether resizing, minimizing, or switching apps interrupts the task.

## Task PH0-004: Confirm offline behavior

With the network disconnected, launch Swar and repeat the native core check.

### Success criteria

- Launch and the diagnostic task work without a network connection.
- No sign-in, cloud permission, or network error blocks the task.
- No personal content leaves the machine.

### Observe

- Any delay caused by hidden network retries.
- Any wording that implies cloud processing.
- Any unexpected outbound-network prompt from the operating system or firewall.

## Task PH0-005: Recover from an interruption

While Swar is open, switch applications, minimize or close its window, and return to it using the platform's normal controls.

### Success criteria

- Swar remains responsive.
- The user can return without restarting the process.
- Visible state does not become misleading after the interruption.

### Observe

- Lost focus, hidden windows, duplicated windows, or stale status.
- Whether the platform behavior matches expectations on older supported systems.

## Session completion

The plan is complete only when every applicable task has a result and every blocked or workaround result has an issue entry. Windows may mark the macOS-only menu bar task as not applicable with a reason.
