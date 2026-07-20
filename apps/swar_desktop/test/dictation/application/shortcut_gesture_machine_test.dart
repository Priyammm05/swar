import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/dictation/application/shortcut_gesture_machine.dart';

void main() {
  test('hold starts on press and finishes immediately on long release', () {
    final machine = ShortcutGestureMachine();

    expect(
      machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0).actions,
      contains(ShortcutGestureAction.start),
    );
    // Held well past the 500ms hold threshold: a deliberate push-to-talk.
    final released = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 800,
    );

    expect(released.actions, contains(ShortcutGestureAction.finish));
    expect(released.state, ShortcutGestureState.idle);
  });

  test('a quick press under the hold threshold is a tap, never a decode', () {
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0);
    // 400ms is below the 500ms threshold: this is a click, not a hold. It must
    // wait for a possible second tap and must NOT finish (decode) on its own.
    final released = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 400,
    );

    expect(released.state, ShortcutGestureState.waitingForSecondTap);
    expect(
      released.actions,
      contains(ShortcutGestureAction.scheduleDoubleTapWindow),
    );
    expect(released.actions, isNot(contains(ShortcutGestureAction.finish)));
  });

  test('short first tap waits and second press latches without restarting', () {
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0);
    final firstRelease = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 80,
    );
    final secondPress = machine.advance(
      ShortcutGestureInput.pressed,
      nowMilliseconds: 180,
    );

    expect(
      firstRelease.actions,
      contains(ShortcutGestureAction.scheduleDoubleTapWindow),
    );
    expect(secondPress.state, ShortcutGestureState.latched);
    expect(secondPress.actions, isNot(contains(ShortcutGestureAction.start)));
    expect(machine.isLatched, isTrue);
  });

  test('a lone tap is discarded, never decoded', () {
    // Regression: a single quick tap used to FINISH (decode) its near-silent
    // blip, which made whisper hallucinate garbage. A lone tap must now cancel.
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0);
    machine.advance(ShortcutGestureInput.released, nowMilliseconds: 50);

    final expired = machine.advance(
      ShortcutGestureInput.doubleTapWindowElapsed,
      nowMilliseconds: 390,
    );

    expect(expired.actions, contains(ShortcutGestureAction.cancel));
    expect(expired.actions, isNot(contains(ShortcutGestureAction.finish)));
    expect(expired.state, ShortcutGestureState.idle);
  });

  test('stopping a latch never leaks into a stuck recording', () {
    // Regression: after the third tap stopped a hands-free latch, a stale
    // release-suppression flag leaked into the NEXT press, so that press started
    // a recording whose release was swallowed — a "recording" with no way to
    // stop it. The upstream release of the stopping press is deliberately NOT
    // delivered here, reproducing the swallow that happens while the stopped
    // recording is still transcribing.
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0);
    machine.advance(ShortcutGestureInput.released, nowMilliseconds: 80);
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 180);
    expect(machine.isLatched, isTrue);

    // Third tap stops the latch (finish). Its paired release is swallowed.
    final stop = machine.advance(
      ShortcutGestureInput.pressed,
      nowMilliseconds: 3000,
    );
    expect(stop.actions, contains(ShortcutGestureAction.finish));
    expect(stop.state, ShortcutGestureState.idle);

    // A brand-new hold must record and finish normally, not be suppressed.
    final newHold = machine.advance(
      ShortcutGestureInput.pressed,
      nowMilliseconds: 5000,
    );
    expect(newHold.actions, contains(ShortcutGestureAction.start));
    final newRelease = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 6000,
    );
    expect(newRelease.actions, contains(ShortcutGestureAction.finish));
    expect(newRelease.state, ShortcutGestureState.idle);
  });

  test('pressing while latched finishes and suppresses its release', () {
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.toggled, nowMilliseconds: 0);
    final stop = machine.advance(
      ShortcutGestureInput.pressed,
      nowMilliseconds: 1,
    );
    final release = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 2,
    );

    expect(stop.actions, contains(ShortcutGestureAction.finish));
    expect(release.actions, isEmpty);
  });

  test('cancel and start failure always return to idle', () {
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.toggled, nowMilliseconds: 0);
    final cancelled = machine.advance(
      ShortcutGestureInput.cancelled,
      nowMilliseconds: 1,
    );
    expect(cancelled.actions, contains(ShortcutGestureAction.cancel));
    expect(cancelled.state, ShortcutGestureState.idle);

    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 2);
    final failed = machine.advance(
      ShortcutGestureInput.startFailed,
      nowMilliseconds: 3,
    );
    expect(failed.state, ShortcutGestureState.idle);
  });
}
