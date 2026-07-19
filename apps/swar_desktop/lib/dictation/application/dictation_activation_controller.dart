import 'dart:async';

import 'package:swar_desktop/dictation/application/shortcut_gesture_machine.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';

/// Owns the push-to-talk gesture independently of Flutter presentation.
final class DictationActivationController {
  DictationActivationController({
    required Future<bool> Function() start,
    required Future<void> Function() finish,
    required Future<void> Function() cancel,
    required void Function() modeChanged,
  }) : _start = start,
       _finish = finish,
       _cancel = cancel,
       _modeChanged = modeChanged;

  // Gap allowed between the first tap's release and the second press to latch.
  // Aligned closer to the macOS double-click interval (~500ms) so a natural
  // double-press reliably locks instead of finishing after the first tap.
  static const _doubleTapWindow = Duration(milliseconds: 480);

  final Future<bool> Function() _start;
  final Future<void> Function() _finish;
  final Future<void> Function() _cancel;
  final void Function() _modeChanged;
  final ShortcutGestureMachine _machine = ShortcutGestureMachine();

  Timer? _releaseTimer;
  bool _isCompleting = false;

  bool get isLatched => _machine.isLatched;
  bool get isCompleting => _isCompleting;

  Future<void> handle(DesktopShortcutEvent event) async {
    // Key events generated while the previous result is being transcribed and
    // inserted are deliberately discarded. Replaying them after completion
    // would start a recording the user did not intend.
    if (_isCompleting) return;
    switch (event.kind) {
      case DesktopShortcutEventKind.pressed:
        await _advance(ShortcutGestureInput.pressed);
      case DesktopShortcutEventKind.released:
        await _advance(ShortcutGestureInput.released);
      case DesktopShortcutEventKind.toggle:
      case DesktopShortcutEventKind.stop:
        await _advance(ShortcutGestureInput.toggled);
      case DesktopShortcutEventKind.cancel:
        await _advance(ShortcutGestureInput.cancelled);
    }
  }

  Future<void> _advance(ShortcutGestureInput input) async {
    final transition = _machine.advance(
      input,
      nowMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    for (final action in transition.actions) {
      switch (action) {
        case ShortcutGestureAction.start:
          if (!await _start()) {
            await _advance(ShortcutGestureInput.startFailed);
          }
        case ShortcutGestureAction.finish:
          if (_isCompleting) continue;
          _isCompleting = true;
          try {
            await _finish();
          } finally {
            _isCompleting = false;
            _modeChanged();
          }
        case ShortcutGestureAction.cancel:
          await _cancel();
        case ShortcutGestureAction.notifyModeChanged:
          _modeChanged();
        case ShortcutGestureAction.scheduleDoubleTapWindow:
          _releaseTimer?.cancel();
          _releaseTimer = Timer(_doubleTapWindow, () {
            unawaited(_advance(ShortcutGestureInput.doubleTapWindowElapsed));
          });
        case ShortcutGestureAction.cancelDoubleTapWindow:
          _releaseTimer?.cancel();
          _releaseTimer = null;
      }
    }
  }

  void dispose() {
    _releaseTimer?.cancel();
  }
}
