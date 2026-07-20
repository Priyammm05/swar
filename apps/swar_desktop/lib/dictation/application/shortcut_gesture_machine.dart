enum ShortcutGestureState { idle, holding, waitingForSecondTap, latched }

enum ShortcutGestureInput {
  pressed,
  released,
  toggled,
  cancelled,
  doubleTapWindowElapsed,
  startFailed,
}

enum ShortcutGestureAction {
  start,
  finish,
  cancel,
  notifyModeChanged,
  scheduleDoubleTapWindow,
  cancelDoubleTapWindow,
}

final class ShortcutGestureTransition {
  const ShortcutGestureTransition({required this.state, required this.actions});

  final ShortcutGestureState state;
  final List<ShortcutGestureAction> actions;
}

/// Pure reducer for hold-to-talk, double-tap lock, and explicit toggle input.
final class ShortcutGestureMachine {
  ShortcutGestureMachine({
    // A press SHORTER than this is a tap: on its own it records nothing (a lone
    // tap is discarded; two taps latch the hands-free lock). A press held LONGER
    // is a deliberate push-to-talk that records while held and transcribes on
    // release. Kept generous so an ordinary quick click is treated as a tap and
    // never decoded — decoding a sub-second, near-silent blip from a stray click
    // is what made whisper hallucinate garbage. Only an intentional hold records.
    this.holdThreshold = const Duration(milliseconds: 500),
  });

  final Duration holdThreshold;
  ShortcutGestureState _state = ShortcutGestureState.idle;
  int? _pressedAtMilliseconds;
  bool _suppressNextRelease = false;

  ShortcutGestureState get state => _state;
  bool get isLatched => _state == ShortcutGestureState.latched;

  ShortcutGestureTransition advance(
    ShortcutGestureInput input, {
    required int nowMilliseconds,
  }) {
    final actions = <ShortcutGestureAction>[];

    if (input == ShortcutGestureInput.startFailed) {
      _reset();
      return ShortcutGestureTransition(
        state: _state,
        actions: const [ShortcutGestureAction.notifyModeChanged],
      );
    }

    switch (input) {
      case ShortcutGestureInput.pressed:
        if (_state == ShortcutGestureState.latched) {
          _suppressNextRelease = true;
          _reset(keepReleaseSuppression: true);
          actions.addAll(const [
            ShortcutGestureAction.cancelDoubleTapWindow,
            ShortcutGestureAction.notifyModeChanged,
            ShortcutGestureAction.finish,
          ]);
        } else if (_state == ShortcutGestureState.waitingForSecondTap) {
          _state = ShortcutGestureState.latched;
          _pressedAtMilliseconds = nowMilliseconds;
          actions.addAll(const [
            ShortcutGestureAction.cancelDoubleTapWindow,
            ShortcutGestureAction.notifyModeChanged,
          ]);
        } else if (_state == ShortcutGestureState.idle) {
          // Clear any stale release-suppression before arming a fresh gesture. A
          // latch-stopping press sets suppression expecting its own release, but
          // that release can be swallowed upstream while the previous result is
          // still transcribing. Without this reset the flag would leak into the
          // next press and suppress its release, leaving a recording that never
          // finishes (a stuck "recording" with no way to stop it).
          _suppressNextRelease = false;
          _state = ShortcutGestureState.holding;
          _pressedAtMilliseconds = nowMilliseconds;
          actions.addAll(const [
            ShortcutGestureAction.notifyModeChanged,
            ShortcutGestureAction.start,
          ]);
        }
      case ShortcutGestureInput.released:
        if (_suppressNextRelease) {
          _suppressNextRelease = false;
        } else if (_state == ShortcutGestureState.holding) {
          final heldFor =
              nowMilliseconds - (_pressedAtMilliseconds ?? nowMilliseconds);
          if (heldFor >= holdThreshold.inMilliseconds) {
            _reset();
            actions.addAll(const [
              ShortcutGestureAction.cancelDoubleTapWindow,
              ShortcutGestureAction.notifyModeChanged,
              ShortcutGestureAction.finish,
            ]);
          } else {
            _state = ShortcutGestureState.waitingForSecondTap;
            actions.add(ShortcutGestureAction.scheduleDoubleTapWindow);
          }
        }
      case ShortcutGestureInput.toggled:
        if (_state == ShortcutGestureState.idle) {
          _state = ShortcutGestureState.latched;
          actions.addAll(const [
            ShortcutGestureAction.notifyModeChanged,
            ShortcutGestureAction.start,
          ]);
        } else {
          _reset();
          actions.addAll(const [
            ShortcutGestureAction.cancelDoubleTapWindow,
            ShortcutGestureAction.notifyModeChanged,
            ShortcutGestureAction.finish,
          ]);
        }
      case ShortcutGestureInput.cancelled:
        if (_state != ShortcutGestureState.idle) {
          _reset();
          actions.addAll(const [
            ShortcutGestureAction.cancelDoubleTapWindow,
            ShortcutGestureAction.cancel,
            ShortcutGestureAction.notifyModeChanged,
          ]);
        }
      case ShortcutGestureInput.doubleTapWindowElapsed:
        if (_state == ShortcutGestureState.waitingForSecondTap) {
          // A lone tap that never became a double-tap: DISCARD it, never decode
          // it. A single quick tap captures only a near-silent blip, and feeding
          // that to whisper is what produced hallucinated garbage. Cancelling
          // throws the capture away; finishing would transcribe it.
          _reset();
          actions.addAll(const [
            ShortcutGestureAction.cancel,
            ShortcutGestureAction.notifyModeChanged,
          ]);
        }
      case ShortcutGestureInput.startFailed:
        break;
    }

    return ShortcutGestureTransition(state: _state, actions: actions);
  }

  void _reset({bool keepReleaseSuppression = false}) {
    _state = ShortcutGestureState.idle;
    _pressedAtMilliseconds = null;
    if (!keepReleaseSuppression) _suppressNextRelease = false;
  }
}
