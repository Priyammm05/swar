# Phase 1 desktop shell

This plan checks whether Swar's first product shell feels clear, private, responsive, and predictable. All history and insight values are sample data in this phase.

## Automation map

The synthetic-user journey covers `SHELL-001`, `SHELL-002`, and the deterministic parts of `SHELL-003`. It opens the real macOS or Windows application, reviews Insights, searches a virtualised history, resizes the window, opens Settings, persists a mock setting, interrupts the lifecycle, and captures screenshots. Human review still decides whether the wording, hierarchy, density, and window behaviour feel natural.

## Preconditions

- Use a release build where possible.
- Keep the computer offline throughout the session.
- Record the operating system version, processor family, memory, display scaling, window size, and appearance mode.
- Remember that dictations and insight totals are sample data. Do not enter private content.

## Task SHELL-001: Understand activity and find a recent dictation

Open Swar, understand what the first page contains, then move to Dictation and find history related to the word `launch`.

### Success criteria

- Insights is clearly the starting page and its values are identified as preview data.
- Dictation is easy to find as the second destination.
- The history feels responsive even though it represents 10,000 records.
- Search changes the visible results without freezing or losing the search field.
- The page makes local storage clear without an alarming privacy claim.

### Observe

- Whether the first page is understandable without product guidance.
- Any delay, scroll jump, clipped text, or uncertainty about what search changed.
- Whether sample history could be mistaken for the person's real data.

## Task SHELL-002: Explore Swar in a smaller window

Make the window narrow, then visit Insights and Settings using the navigation that remains available.

### Success criteria

- Navigation adapts without hiding either product destination or Settings.
- Insights and Dictation remain reachable, and Settings opens as a dialog with General and System sections.
- No text, card, control, or navigation label is clipped or overlapped.
- Insights clearly identifies its values as preview data.

### Observe

- Any hesitation caused by navigation moving from the sidebar to the bottom.
- Awkward scrolling, crowded controls, overflow, or unexpected window resizing.
- Whether the information hierarchy still makes sense at the smallest supported size.

## Task SHELL-003: Change a setting and return after interruption

Turn on launch at login in System Settings. Close and reopen Settings, switch to another application, and then return to Swar.

### Success criteria

- The changed setting remains selected while the app is running.
- The app remains responsive after switching away and returning.
- The system check still completes and explains its result in plain language.
- Controls planned for later phases do not pretend to work.

### Observe

- Any doubt about whether a setting was saved.
- Lost state, duplicated windows, stale status, or inaccessible controls.
- Whether the system-check language sounds like product copy or developer diagnostics.

## Session completion

The plan is complete only when every applicable task has a result and every workaround or blocked result has an issue entry. Run it on both macOS and Windows before a public Phase 1 release, including at least one Intel Mac or the oldest supported Windows hardware class when available.
