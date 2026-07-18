import 'dart:async';

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

  static const _holdThreshold = Duration(milliseconds: 260);
  static const _doubleTapWindow = Duration(milliseconds: 340);

  final Future<bool> Function() _start;
  final Future<void> Function() _finish;
  final Future<void> Function() _cancel;
  final void Function() _modeChanged;

  Timer? _releaseTimer;
  DateTime? _pressedAt;
  bool _active = false;
  bool _latched = false;
  bool _ignoreNextRelease = false;

  bool get isLatched => _latched;

  Future<void> handle(DesktopShortcutEvent event) async {
    switch (event.kind) {
      case DesktopShortcutEventKind.pressed:
        await _pressed();
      case DesktopShortcutEventKind.released:
        await _released();
      case DesktopShortcutEventKind.toggle:
      case DesktopShortcutEventKind.stop:
        await _toggle();
      case DesktopShortcutEventKind.cancel:
        await _cancelActive();
    }
  }

  Future<void> _pressed() async {
    _pressedAt = DateTime.now();
    if (_latched) {
      _ignoreNextRelease = true;
      await _finishActive();
      return;
    }
    if (_releaseTimer?.isActive ?? false) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      _latched = true;
      _modeChanged();
      return;
    }
    if (_active) return;
    _active = true;
    _modeChanged();
    if (!await _start()) {
      _reset();
    }
  }

  Future<void> _released() async {
    if (_ignoreNextRelease) {
      _ignoreNextRelease = false;
      return;
    }
    if (!_active || _latched) return;
    final heldFor = DateTime.now().difference(_pressedAt ?? DateTime.now());
    if (heldFor >= _holdThreshold) {
      await _finishActive();
      return;
    }
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_doubleTapWindow, () {
      unawaited(_finishActive());
    });
  }

  Future<void> _toggle() async {
    if (_active) {
      await _finishActive();
    } else {
      _active = true;
      _latched = true;
      _modeChanged();
      if (!await _start()) _reset();
    }
  }

  Future<void> _cancelActive() async {
    if (!_active) return;
    _releaseTimer?.cancel();
    await _cancel();
    _reset();
  }

  Future<void> _finishActive() async {
    if (!_active) return;
    _releaseTimer?.cancel();
    _active = false;
    _latched = false;
    _modeChanged();
    await _finish();
  }

  void _reset() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _active = false;
    _latched = false;
    _modeChanged();
  }

  void dispose() {
    _releaseTimer?.cancel();
  }
}
