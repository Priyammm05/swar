# Swar individual-user testing

Swar's automated tests answer whether the code behaves as specified. Synthetic-user testing runs complete journeys against the real app and captures visual evidence. Human testing answers whether the product behaves well for a person doing real work.

No single participant owns quality. Swar uses deterministic checks, synthetic-user journeys, and human sessions together.

## What every user-facing feature needs

Before implementation, define:

1. The outcome the person is trying to achieve.
2. A realistic task with no instructions that reveal the intended UI path.
3. The normal path, interruption path, failure path, and recovery path.
4. Observable success criteria.
5. Privacy and trust checks.
6. Compatibility conditions, including older supported hardware when relevant.

After implementation:

1. Add or update automated tests for deterministic behavior.
2. Run the relevant task scenario as an individual user.
3. Record what happened, including confusion and workarounds.
4. Classify each issue by user impact.
5. Turn every repeatable defect into an automated regression test when practical.
6. Rerun the original task after the fix.

## Evidence layers

| Layer | What it catches | Where it lives |
| --- | --- | --- |
| Rust and Dart unit tests | Domain rules, state transitions, edge cases | `crates/*` and `apps/swar_desktop/test` |
| Widget tests | UI states, semantics, keyboard interaction | `apps/swar_desktop/test` |
| Native integration tests | Flutter, Rust, and operating-system boundaries | `apps/swar_desktop/integration_test` |
| Synthetic-user journeys | Real UI tasks, accessibility semantics, resizing, interruptions, repeated actions, screenshots | `apps/swar_desktop/integration_test` and CI artifacts |
| Individual-user scenarios | Confusion, trust, workflow friction, recovery, perceived latency | `quality/user-testing/scenarios` |
| Private session reports | Actual observations from a specific run | `.user-testing/sessions` |

## Session workflow

Run the complete automated framework first:

```sh
./scripts/run_test_framework.sh full
```

This runs Rust unit tests, architecture checks, Dart unit and widget tests, the local pipeline benchmark, the real Flutter-to-Rust desktop bridge, and the synthetic-user journey. Use `fast` instead of `full` while iterating when native desktop launch evidence is not required.

The synthetic user can also be run independently:

```sh
./scripts/run_synthetic_user_test.sh
```

It writes a JSON report and screenshots under `apps/swar_desktop/build/user-testing/synthetic-user`. CI runs the same journey on macOS and Windows and uploads the evidence.

Create a private report:

```sh
./scripts/start_user_test.sh phase-1-shell
```

Run the tasks in order. Do not coach yourself through the interface. Record the first place where your expectation and the product differ. A workaround still counts as a problem.

Automation can prove that a control is visible, labelled, enabled, responsive, and stable across a scripted journey. It cannot prove that the wording feels natural, that an icon communicates the right meaning, or that a transcript still sounds like the person. Those remain human judgments.

Session files are deliberately ignored by Git. Do not commit audio, raw transcripts, names, email addresses, or other personal content. Copy only sanitized findings into an issue or release summary.

## Measures

Record these for each scenario:

- Task result: completed, completed with workaround, or blocked.
- Time and perceived delay.
- Wrong turns or moments of hesitation.
- Correction effort.
- Recovery success after interruption or failure.
- Trust: whether the app made recording, storage, and insertion state clear.
- Voice fidelity: whether the result still sounds like the person.

## Severity

| Level | User impact |
| --- | --- |
| S0 | Privacy breach, data loss, unsafe behavior, or content inserted without clear intent |
| S1 | Core task blocked with no reasonable recovery |
| S2 | Core task completed only with a confusing or expensive workaround |
| S3 | Noticeable friction that does not block completion |
| S4 | Cosmetic or low-impact polish issue |

S0 and S1 issues block a release. S2 issues require an explicit release decision. Repeated S3 issues should be treated as a product problem, not dismissed as isolated polish.

## Adding a feature

Create a scenario file before calling the feature complete. Give every scenario a stable ID such as `DICT-001`. Keep that ID when the scenario evolves so reports and regression tests remain traceable.

Then add the plan name to `quality/user-testing/scenarios/manifest.txt`. CI verifies that every listed plan exists and contains the required task and observation sections.
