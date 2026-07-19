import 'dart:async';

import 'package:flutter/services.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';

/// Thin platform adapter. Native runners own the actual global registration.
final class PlatformDesktopShortcutGateway implements DesktopShortcutGateway {
  static const _channel = MethodChannel('dev.swar/desktop');
  final _events = StreamController<DesktopShortcutEvent>.broadcast();

  @override
  Stream<DesktopShortcutEvent> get events => _events.stream;

  @override
  Future<bool> initialize() async {
    _channel.setMethodCallHandler((call) async {
      final kind = switch (call.method) {
        'dictationKeyPressed' => DesktopShortcutEventKind.pressed,
        'dictationKeyReleased' => DesktopShortcutEventKind.released,
        'shortcutPressed' => DesktopShortcutEventKind.toggle,
        'overlayStopPressed' => DesktopShortcutEventKind.stop,
        'overlayCancelPressed' => DesktopShortcutEventKind.cancel,
        _ => null,
      };
      if (kind != null) _events.add(DesktopShortcutEvent(kind));
    });
    return await _channel.invokeMethod<bool>('registerGlobalShortcut') ?? false;
  }

  @override
  Future<bool> requestInsertionPermission() async {
    return await _channel.invokeMethod<bool>('requestInsertionPermission') ??
        true;
  }

  @override
  Future<String> foregroundApplication() async {
    return await _channel.invokeMethod<String>('foregroundApplication') ?? '';
  }

  @override
  Future<bool> configureShortcut(String shortcutKey) async {
    return await _channel.invokeMethod<bool>('configureGlobalShortcut', {
          'shortcutKey': shortcutKey,
        }) ??
        false;
  }

  @override
  Future<void> updateOverlay({
    required DesktopOverlayState state,
    required double audioLevel,
    required bool isLatched,
    required String shortcutKey,
  }) {
    return _channel.invokeMethod<void>('updateDictationOverlay', {
      'state': state.name,
      'audioLevel': audioLevel,
      'isLatched': isLatched,
      'shortcutKey': shortcutKey,
    });
  }

  @override
  Future<void> hideOverlay() =>
      _channel.invokeMethod<void>('hideDictationOverlay');

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('unregisterGlobalShortcut');
    await _events.close();
  }
}
