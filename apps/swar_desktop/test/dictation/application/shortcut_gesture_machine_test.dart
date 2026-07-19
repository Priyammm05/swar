import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/dictation/application/shortcut_gesture_machine.dart';

void main() {
  test('hold starts on press and finishes immediately on long release', () {
    final machine = ShortcutGestureMachine();

    expect(
      machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0).actions,
      contains(ShortcutGestureAction.start),
    );
    final released = machine.advance(
      ShortcutGestureInput.released,
      nowMilliseconds: 300,
    );

    expect(released.actions, contains(ShortcutGestureAction.finish));
    expect(released.state, ShortcutGestureState.idle);
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

  test('expired short tap finishes the active recording', () {
    final machine = ShortcutGestureMachine();
    machine.advance(ShortcutGestureInput.pressed, nowMilliseconds: 0);
    machine.advance(ShortcutGestureInput.released, nowMilliseconds: 50);

    final expired = machine.advance(
      ShortcutGestureInput.doubleTapWindowElapsed,
      nowMilliseconds: 390,
    );

    expect(expired.actions, contains(ShortcutGestureAction.finish));
    expect(expired.state, ShortcutGestureState.idle);
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
