# Phase 2 local dictation

This plan validates Swar as a real offline voice-typing product. It exercises the same focused controls, short utterances, language changes, interruptions, and recovery paths that an individual user encounters. It is not a smoke test.

## Automation map

The Rust suite covers capture boundaries, speech retention, language decoding, text cleanup, protected tokens, clipboard ownership, storage, and coordinator transitions. The ASR benchmark runs real local models for English, Hindi, and Hinglish, including short Automatic-mode speech. The Flutter synthetic user starts and finishes a dictation, verifies processing lockout, refreshes history, paginates activity, persists Settings, and checks compact navigation. `DICT-003` still requires an installed, accessibility-authorized release because operating-system focus and insertion cannot be faithfully simulated inside a widget process.

## Preconditions

- Install a signed release build and grant Microphone and Accessibility access to Swar itself.
- Disconnect from the internet after model installation.
- Select Automatic language, the built-in microphone, Option as the shortcut, and automatic paste.
- Open one native text field, one Electron text field, and one browser content-editable field.
- Record the operating system, processor architecture, selected model, microphone, and target application.

## Task DICT-001: Dictate short and long speech in Automatic mode

In each target field, dictate a one-second English sentence, a longer English paragraph, a Hindi sentence, and a natural Hinglish sentence.

### Success criteria

- Every non-silent recording produces text instead of an empty result.
- English, Hindi, and Hinglish are recognised without changing the language selector.
- Mixed-language speech is not translated into a different meaning.
- Processing stays offline and the interface remains responsive.
- Silence does not create a history record or hallucinated text.

### Observe

- Any language that returns no text, uses the wrong script, or changes the speaker's meaning.
- Whether short phrases feel noticeably slower or less reliable than longer speech.
- Any waveform activity that does not correspond to the selected microphone.

## Task DICT-002: Use hold and hands-free shortcut modes

Hold Option while speaking and release it to finish. Then double-tap Option, speak without holding it, and press Option once to finish.

### Success criteria

- Recording begins once for each gesture.
- The overlay distinguishes idle, recording, and finalising states.
- A new recording cannot begin until transcription, cleanup, insertion, and history persistence finish.
- Cancel discards the recording and returns to idle.

### Observe

- Duplicate starts, missed releases, stuck finalising states, or abrupt overlay transitions.
- Whether the overlay blocks content, steals focus, or makes completion timing unclear.

## Task DICT-003: Insert into real focused controls

Repeat a short dictation in the native, Electron, and browser fields. Keep focus in the target until Swar finishes.

### Success criteria

- The target field receives the final text once, at the original cursor position.
- The Swar overlay never steals focus.
- If automatic insertion is unavailable, the same final text remains on the clipboard and Command+V works.
- Accessibility is requested for Swar, not the terminal, Cursor, or another parent process.
- No transcript or clipboard content appears in logs.

### Observe

- The exact target application and control type for any missing, duplicated, or misplaced insertion.
- Whether clipboard fallback remains available long enough to use manually.

## Task DICT-004: Verify activity and paging

Complete 6 dictations, then 50, then more than 50 using generated non-private phrases.

### Success criteria

- With 6 records, all 6 appear and no Show More action is displayed.
- With exactly 50 records, no Show More action is displayed.
- With more than 50, the first 50 appear; Show More loads the remaining page and disappears when no records remain.
- A completed dictation refreshes history promptly without reopening the page.
- Blank-audio attempts never appear as `[BLANK_AUDIO]` or another fake record.

### Observe

- Missing rows, duplicate rows, stale totals, unexpected Show More controls, or scroll jumps.
- Any delay between overlay completion and the new activity becoming visible.

## Task DICT-005: Recover from closure and interruption

Close the main window, reopen Swar from the Dock and menu bar, switch applications during recording, and repeat after a failed or silent recording.

### Success criteria

- Clicking the Dock icon reopens the existing application window.
- Closing the window does not terminate the shortcut or menu-bar service.
- A handled failure releases the coordinator so the next recording can start.
- Swar never crashes after finishing transcription.

### Observe

- Hidden windows, duplicate instances, stale shortcut state, or permissions requested again.
- Whether recovery requires a workaround that an ordinary user would not discover.

## Session completion

The session is complete only when every applicable target and language has evidence. Record failures against the exact target application, shortcut mode, language, and stage. Never attach private dictated text or raw audio to an issue.
