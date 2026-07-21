# Dictation overlay specification

This is the source of truth for Swar's floating dictation overlay — the small
capsule that appears over every application while you dictate. The reference
design is `swar/overlay/overlay_states.png`. The implementation must match it
exactly, and every transition must be **one continuous, smooth morph** — never a
pop, a swap, or a second element appearing on top.

The overlay is **native** (macOS `NSPanel` drawn with Core Graphics in
`apps/swar_desktop/macos/Runner/MainFlutterWindow.swift`; Windows: a topmost
`WS_EX_NOACTIVATE` window). Flutter never renders it — it only pushes a state
snapshot over a method channel. Raw PCM never leaves Rust. Keep it native so it
stays above other apps, never steals text-field focus, and stays smooth while
Flutter and Rust do other work.

---

## 1. The one rule: a single capsule that morphs in place

There is exactly **one** object on screen: a dark capsule. Every state below is
that same capsule changing its width, height, corner radius, and contents. It
must feel like one physical pill that grows, shrinks, and re-labels itself.

- Never spawn a second floating element. The live transcript in states 3b and 4
  is drawn *inside* the capsule (the capsule grows taller), not in a bubble above
  it.
- Geometry (width, height, radius) is always animated, never snapped.
- Content changes cross-fade; the capsule outline morphs underneath them.
- The capsule is dark in both app themes (the app is light-mode only; the bar is
  the one dark surface).
- It never takes keyboard focus and never becomes key/main window.
- At rest it ignores mouse events so a stray click cannot start dictation; it
  becomes interactive only when it has controls to offer.

---

## 2. Palette, type, geometry

Colors (already in `OverlayPalette`, matching the brand):

| Token | Hex | Use |
| --- | --- | --- |
| `pillBg` | `#1C1F1E` @ ~0.99 | capsule fill |
| `pillBgAlt` | `#26302B` | inset chips (cancel/lock slot) |
| `onPill` | `#FFFFFF` | final text, primary label |
| `onPillSoft` | `#C9D2CE` | secondary label |
| `onPillMut` | `#9AA6A0` | not-yet-final transcript, muted icons, elapsed |
| `spruce` | `#2F5547` | confirm / stop button, success check ring |
| `saffron` | `#F4B24A` | waveform, processing dots, download/attention icon |
| warn amber | `#F4B24A` (icon) on `pillBg` | ⚠ warning glyph |

- Type: Manrope (the app UI face), weights 400/500. Elapsed and timers use
  tabular figures so digits do not jitter.
- Compact states are a **full pill**: corner radius = height / 2.
- Transcript states (3b, 4) are a **rounded rectangle**: corner radius ~18 pt,
  because the capsule is now tall enough that a full pill would look wrong.
- Sizes are deliberately small and unobtrusive (a menu-bar-scale accessory, not a
  toolbar). Target geometries:
  - Resting dock (state 1): **33 × 8**, radius 4 — a subtle sliver, no content.
  - Ready (state 2): ~128 × 30, radius 15.
  - Recording row (state 3): ~184 × 32, radius 16.
  - Processing (state 5) / message states (6–11): ~140 × 28, radius 14, width
    growing to fit the label.
  - Transcript (3b, 4): width ~300–340, height grows per line (cap ~2 lines,
    then the oldest scrolls up out of view).
- Horizontal padding 12 pt; 8 pt between row items. Waveform bars max ~18 pt tall.
- Panel size is **dynamic** — the capsule reports its target size each frame and
  the `NSPanel` frame animates to it (see §5). The current fixed 108×60 panel
  must become size-following.

---

## 3. The eleven states

Each state lists its **trigger**, its **exact contents left→right**, and any
per-state motion. Numbers match the reference image.

### 1 · Idle
- **Trigger:** no active dictation; overlay visible (Settings "Show Swar bar").
- **Contents:** one small empty dark capsule. No icon, no text. ~44×7 at rest,
  growing to the standard 30 pt height as it wakes.
- **Behaviour:** draggable, snaps to screen edges, never steals focus. This is
  the shape every other state collapses back to.

### 2 · Ready
- **Trigger:** a normal (non-secure) text field gains focus.
- **Contents:** the same capsule widens a touch and shows `Dictate` + the
  shortcut glyph (`⌥` or `⌃` per the user's setting). No new element — it grows.
- **Note:** this replaces today's *hover*-triggered hint. Ready is driven by
  **focus**, not by the mouse hovering the bar.

### 3 · Recording
- **Trigger:** dictation recording (hold, before any transcript arrives).
- **Contents (row):** `✕` cancel (in a `pillBgAlt` circle) · live **waveform**
  (real audio, saffron bars) · language chip (`HI+EN`) · elapsed (`0:07`,
  muted) · `✓` stop (in a spruce circle).
- **Motion:** waveform tracks real audio with a per-bar smoothed follower and a
  faint ambient sine so it is never dead flat; elapsed ticks each second.

### 3b · Recording + live transcript
- **Trigger:** recording, once partial transcript text exists.
- **Contents:** the SAME capsule grows **taller**. Top: transcript — final words
  in `onPill` white, not-yet-final tail in `onPillMut` grey. Below: the full
  recording row from state 3.
- **Rule:** one continuous element. The text is inside the capsule; nothing
  floats above it. Height morphs smoothly as lines are added.

### 4 · Locked (hands-free)
- **Trigger:** double-tap latches recording (`isLatched`).
- **Contents:** same as 3b, except the cancel slot becomes a **lock chip** (🔒)
  and the language/label area reads `locked`. Confirm (`✓`) still present.
- **Behaviour:** recording continues without holding the key; tap ✓ to finish,
  lock/✕ to cancel.

### 5 · Processing
- **Trigger:** key released / latch confirmed; transcription + cleanup running
  (lifecycle `finalising`/`transcribing`/`cleaning`/`enhancing`/`inserting`).
- **Contents:** the capsule shrinks to a compact label with three animated dots:
  `● ● ● Understanding…`. The word tracks the writing mode:
  - Raw → `Transcribing…`
  - Clean → `Cleaning…`
  - Intent → `Understanding…`
- **Motion:** dots pulse in sequence (saffron). No spinner arc — dots only, per
  the reference.

### 6 · Success
- **Trigger:** text inserted at the cursor.
- **Contents:** spruce circle with a white check that draws in, then `Inserted`.
- **Behaviour:** hold ~600 ms, then the capsule **collapses back to the idle
  pill** (state 1) in one morph.

### 7 · Error (copied fallback)
- **Trigger:** insertion failed, so the text was copied to the clipboard instead
  (lifecycle `copiedFallback`).
- **Contents:** ⚠ amber glyph + `Couldn't insert — copied`.
- **Rule:** never a dead end — the user still has their words on the clipboard.
  Hold, then collapse to idle.

### 8 · Permission needed
- **Trigger:** microphone or Accessibility permission missing when the user tries
  to dictate.
- **Contents:** ⚠ `Allow microphone` + a `⋯` affordance on the right.
- **Behaviour:** tapping opens the correct Settings pane. Recording is blocked
  until granted.

### 9 · Model missing
- **Trigger:** no verified offline voice model installed.
- **Contents:** ⬇ `Download voice model` (saffron download glyph).
- **Behaviour:** tapping starts the model download (the Settings install flow).

### 10 · No text field
- **Trigger:** dictation invoked with nothing focused (or a non-text control).
- **Contents:** ⚠ `Click a text field first`.
- **Behaviour:** prompts, and copies the captured speech as a fallback so nothing
  is lost.

### 11 · Private field
- **Trigger:** the focused field is a password / OTP / payment field (secure).
- **Contents:** 🔒 `Private field — history off`.
- **Behaviour:** history is not written and the field is never read back. This is
  the visible confirmation of the existing secure-field privacy guarantee.

---

## 4. State machine

The overlay state is a pure function of dictation lifecycle **plus** environment
conditions. Conditions are checked first, because a permission/model/field
problem overrides the normal flow.

```
if secure field focused            -> 11 Private field
elif mic/accessibility missing     -> 8  Permission needed   (on dictate attempt)
elif no verified model             -> 9  Model missing        (on dictate attempt)
elif no text field focused         -> 10 No text field        (on dictate attempt)
else map the lifecycle state:
   preparing                       -> (brief) 3 Recording (arming)
   recording + no transcript       -> 3  Recording
   recording + transcript          -> 3b Recording + transcript
   recording + latched             -> 4  Locked (with transcript row)
   finalising/transcribing/
     cleaning/enhancing/inserting  -> 5  Processing (label per writing mode)
   completed (inserted)            -> 6  Success -> then Idle
   copiedFallback                  -> 7  Error (copied) -> then Idle
   cancelled/failed/idle           -> 1  Idle (or hidden if "Show Swar bar" off)
   text field focused, no session  -> 2  Ready
   nothing focused, no session     -> 1  Idle
```

Today `swar_app.dart` collapses everything after recording into a single
`finalising` overlay state and only distinguishes idle/preparing/recording/
finalising. To reach the eleven states the Dart→native contract must carry more
(see §6): the writing mode, the live transcript (final + partial split), the
language label, elapsed seconds, the latch flag (already sent), and the
condition reason (secure / permission / model / no-field / inserted / copied).

---

## 5. Motion — how it stays "insanely smooth"

All motion runs off the existing single 60 fps timer in the panel. No frame does
layout work heavier than a few interpolations. The feel comes from three layers
animating on slightly different clocks.

### 5.1 Geometry morph (the capsule itself)
- The capsule has three animated scalars: `width`, `height`, `radius`. Each
  state defines a **target** for all three.
- Integrate them as a light spring per frame (position/velocity), not a bare
  lerp — a spring gives the organic settle that reads as premium:
  - Size: stiffness ~200, damping ratio ~0.9 (≈ 180–240 ms settle, no visible
    overshoot). A whisper of overshoot (ratio ~0.8) is allowed on *grow*
    (idle→ready→recording) for delight; use no overshoot on *shrink* so
    Processing/Success feel decisive.
  - Radius follows height: `radius = min(height/2, 20)`.
- Because width/height/radius are continuous, idle→ready→recording→transcript is
  literally one pill stretching. This is the whole aesthetic.

### 5.2 Content cross-fade
- Each "layer" (idle, ready label, recording row, transcript, processing,
  success, and each message state) has a `progress` in [0,1] eased toward its
  target (`progress += (target - progress) * 0.20`, ≈150 ms).
- The geometry morph **leads** by ~40 ms; content fades in after the shape has
  started moving, so text never overflows a capsule that has not grown yet.
- Outgoing content fades to 0 and scales to 0.96; incoming fades from 0 and
  scales from 0.98 → 1. Keep scale subtle.

### 5.3 The living details
- **Waveform:** N bars (target 14–16). Each bar height is
  `max(floor, strength * maxH * multiplier)` where `strength` blends a per-bar
  ambient sine with the smoothed audio follower (`displayed += (target-displayed)
  * 0.18`, target decays `* 0.955`). Never flat, never clipped. Saffron.
- **Processing dots:** three dots, opacity/scale pulse in sequence
  (`sin(phase*1.45 - i*0.6)`), saffron. Label cross-fades when the writing mode
  word changes.
- **Success check:** the check path draws in (stroke-dash reveal ~180 ms) inside
  a spruce ring that scales 0.9→1 with a tiny overshoot, holds ~600 ms, then the
  whole capsule springs down to the idle pill.
- **Transcript streaming:** new final words fade in over ~120 ms; the muted tail
  (partial) updates in place; when a second line is needed the block eases up by
  one line-height. Cap at 2 lines, oldest scrolls out.
- **Elapsed:** ticks once per second; digits use tabular figures so width is
  stable (no horizontal jitter as `0:09`→`0:10`).
- **Idle breathing (optional, subtle):** at most a ±2% opacity drift; the design
  shows a plain pill, so keep this barely perceptible or off.

### 5.4 Timing summary
| Transition | Target feel |
| --- | --- |
| idle → ready | ~160 ms grow, tiny overshoot |
| ready → recording | ~200 ms grow into the row |
| recording → +transcript | height springs per line, ~180 ms |
| release → processing | ~180 ms decisive shrink, no overshoot |
| processing → success | ~150 ms, then check draw-in |
| success → idle | ~220 ms collapse after 600 ms hold |
| any message (7–11) | ~160 ms in, hold, ~200 ms out |

---

## 6. Data contract (Dart → native)

Method channel `dev.swar/desktop`, message `updateDictationOverlay`. Extend the
current map (`state`, `audioLevel`, `isLatched`, `shortcutKey`) with:

| Key | Type | Meaning |
| --- | --- | --- |
| `state` | string | lifecycle state name (existing) |
| `audioLevel` | double | 0–1 smoothed input level (existing) |
| `isLatched` | bool | hands-free latch (existing) |
| `shortcutKey` | string | `option`/`control` for the Ready glyph (existing) |
| `condition` | string? | `secure` / `permission` / `model` / `noField` / `copied` / `inserted` / null — drives states 6–11 |
| `transcriptFinal` | string | confirmed words (white) |
| `transcriptPartial` | string | not-yet-final tail (muted) |
| `language` | string | chip label, e.g. `HI+EN` / `EN` / `HI` |
| `elapsedMs` | int | recording elapsed for the timer |
| `writingMode` | string | `raw`/`clean`/`intent` → Processing label |

Everything the overlay renders is already known to Flutter/Rust today
(`partialText`, the secure-field check, permission and model status, the
`copiedFallback` lifecycle state, the configured/detected language, the writing
mode). This is wiring, not new capability. Raw PCM still never crosses into Dart
— only the numeric `audioLevel` does.

---

## 7. Placement, drag, and snap

- Default position: bottom-center of the active screen's `visibleFrame`, ~10 pt
  above the bottom (current behaviour).
- **Draggable:** `mouseDragged` moves the panel; the capsule is the drag handle
  in every state that has controls, and the whole pill is draggable in Idle/Ready.
- **Snap:** on release, ease to the nearest screen edge (left/right/bottom) with
  a margin, using the same size spring. Remember the snapped anchor per screen so
  it returns there next time.
- Multi-display: follow the screen that owns the focused window; re-clamp into
  that screen's `visibleFrame`.
- Never cover the caret: if the snapped position would sit under the focused
  field, nudge to the opposite edge.

---

## 8. Non-negotiables (accessibility & focus)

- The panel is `.nonactivatingPanel`, `canBecomeKey = false`,
  `canBecomeMain = false`. Dictation must never move focus off the user's field.
- At rest `ignoresMouseEvents = true`; enable hit-testing only for the specific
  control rects (cancel, confirm, lock, the tappable message states 8/9) while
  those controls are shown.
- Honor "Show Swar bar": when off, Idle hides entirely and only appears for an
  active session or an actionable message (permission/model).
- Every error path resolves to a message the user can act on, then returns to
  Idle. The overlay is never a dead end and never a silent failure.

---

## 9. Gap vs. today (implementation checklist)

Done:

1. A **fixed transparent envelope** panel with the capsule anchored bottom-center
   inside it, rather than resizing the window each frame. Resizing an `NSPanel`
   at 60 fps thrashes the window server and janks the morph.
2. The **spring integrator** (§5.1) drives width, height, and radius.
3. States implemented: Idle (1), Ready (2), Recording (3) with language chip and
   elapsed timer, in-capsule **live transcript** (3b), Locked lock-chip and
   `locked` label (4), Processing with the **writing-mode label** (5, no spinner
   arc), Success (6), and the message states (7, 9, 11). Each condition is the
   same capsule with one glyph and one sentence, sized to its own text.
4. The method-channel contract (§6) is extended and `_syncOverlay` in
   `swar_app.dart` sends condition, transcript, language, elapsed, and writing
   mode as one `DesktopOverlaySnapshot`.
5. Hover release polls `NSEvent.mouseLocation` rather than relying on mouse-moved
   events, which stop arriving once the pill becomes hit-testable.

Remaining:

1. **Ready on focus** (2). Ready is currently hover-driven. Driving it from
   text-field focus needs a native focused-role watcher, not just the existing
   secure-field check.
2. **State 8 (permission)** and **state 10 (no text field)** are drawn but not
   yet reachable. Nothing in the pipeline distinguishes "invoked with no text
   field focused" from a failed insertion, which already surfaces as `copied`.
3. **Drag + edge-snap** (§7).

Do not change the app's light-mode theme, the focus/nonactivating guarantees, or
the secure-field privacy behaviour while doing any of the above.
