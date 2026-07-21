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
        'overlayInstallModelPressed' => DesktopShortcutEventKind.installModel,
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
  Future<bool> focusedFieldIsSecure() async {
    // Native returns null when Accessibility is unavailable/unreadable; default
    // to non-sensitive so dictation still works, and the caller can log coverage.
    return await _channel.invokeMethod<bool>('focusedFieldIsSecure') ?? false;
  }

  @override
  Future<FocusedFieldText> focusedFieldText() async {
    // Native returns null for a secure field or when Accessibility cannot read
    // the element; both mean "no context", never a guess.
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'focusedFieldText',
    );
    if (value == null) return const FocusedFieldText();
    return FocusedFieldText(
      before: value['before'] as String? ?? '',
      after: value['after'] as String? ?? '',
    );
  }

  @override
  Future<bool> configureShortcut(String shortcutKey) async {
    return await _channel.invokeMethod<bool>('configureGlobalShortcut', {
          'shortcutKey': shortcutKey,
        }) ??
        false;
  }

  @override
  Future<void> updateOverlay(DesktopOverlaySnapshot snapshot) {
    return _channel.invokeMethod<void>('updateDictationOverlay', {
      'state': snapshot.state.name,
      'audioLevel': snapshot.audioLevel,
      'isLatched': snapshot.isLatched,
      'shortcutKey': snapshot.shortcutKey,
      // Absent rather than null when there is no exceptional condition, so the
      // native side reads one shape.
      if (snapshot.condition != null) 'condition': snapshot.condition!.name,
      'transcriptFinal': snapshot.transcriptFinal,
      'transcriptPartial': snapshot.transcriptPartial,
      'language': snapshot.language,
      'elapsedMs': snapshot.elapsedMs,
      'writingMode': snapshot.writingMode.name,
      'downloadPercent': snapshot.downloadPercent,
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
