# User validation release gate

A release candidate is ready only when all applicable statements are true.

## Automated evidence

- Unit, widget, integration, native, and build checks pass.
- Synthetic-user journeys pass on macOS and Windows, with reports and screenshots retained as build evidence.
- Known repeatable defects have regression coverage where practical.
- Supported macOS and Windows build artifacts were tested, not only debug builds.

## Individual-user evidence

- Every changed user-facing flow has a stable task scenario.
- At least one clean session was run without coaching for each changed flow.
- macOS and Windows were both covered when platform behavior differs.
- Older supported operating systems or hardware were covered when the change touches compatibility-sensitive code.
- Accessibility, interruption, failure, recovery, and offline behavior were checked where relevant.
- No S0 or S1 issue remains open.
- Every open S2 issue has a written release decision.

## Privacy evidence

- Raw session notes remain local.
- Shared findings contain no personal audio or transcript content.
- Network-disconnected behavior was checked for offline features.
- Recording, processing, storage, and insertion states are clear to the tester.

## Sign-off

Record the tested build, scenario IDs, platforms, sanitized issue IDs, and the person making the release decision. A passing CI run alone cannot satisfy this gate.
