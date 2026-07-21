import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/dictation/application/dictation_activation_controller.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';

void main() {
  test(
    'ignores every new shortcut while completion is still running',
    () async {
      final completion = Completer<void>();
      var startCalls = 0;
      var finishCalls = 0;
      final controller = DictationActivationController(
        start: () async {
          startCalls += 1;
          return true;
        },
        finish: () {
          finishCalls += 1;
          return completion.future;
        },
        cancel: () async {},
        modeChanged: () {},
        installModel: () async {},
      );
      addTearDown(controller.dispose);

      await controller.handle(
        const DesktopShortcutEvent(DesktopShortcutEventKind.toggle),
      );
      final finishing = controller.handle(
        const DesktopShortcutEvent(DesktopShortcutEventKind.toggle),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.isCompleting, isTrue);
      await controller.handle(
        const DesktopShortcutEvent(DesktopShortcutEventKind.pressed),
      );
      await controller.handle(
        const DesktopShortcutEvent(DesktopShortcutEventKind.toggle),
      );
      expect(startCalls, 1);
      expect(finishCalls, 1);

      completion.complete();
      await finishing;
      expect(controller.isCompleting, isFalse);

      await controller.handle(
        const DesktopShortcutEvent(DesktopShortcutEventKind.toggle),
      );
      expect(startCalls, 2);
    },
  );

  test('the overlay install click runs the install and no gesture', () async {
    var startCalls = 0;
    var installCalls = 0;
    final controller = DictationActivationController(
      start: () async {
        startCalls += 1;
        return true;
      },
      finish: () async {},
      cancel: () async {},
      modeChanged: () {},
      installModel: () async => installCalls += 1,
    );
    addTearDown(controller.dispose);

    await controller.handle(
      const DesktopShortcutEvent(DesktopShortcutEventKind.installModel),
    );

    expect(installCalls, 1);
    // The gesture machine must not have seen it: a click on the model capsule
    // is not a press, and must not begin recording.
    expect(startCalls, 0);
    expect(controller.isLatched, isFalse);
  });
}
