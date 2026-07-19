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
}
