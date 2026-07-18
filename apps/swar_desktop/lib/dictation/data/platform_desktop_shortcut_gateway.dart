import 'dart:async';

import 'package:flutter/services.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';

/// Thin platform adapter. Native runners own the actual global registration.
final class PlatformDesktopShortcutGateway implements DesktopShortcutGateway {
  static const _channel = MethodChannel('dev.swar/desktop');
  final _activations = StreamController<void>.broadcast();

  @override
  Stream<void> get activations => _activations.stream;

  @override
  Future<bool> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shortcutPressed') _activations.add(null);
    });
    return await _channel.invokeMethod<bool>('registerGlobalShortcut') ?? false;
  }

  @override
  Future<bool> requestInsertionPermission() async {
    return await _channel.invokeMethod<bool>('requestInsertionPermission') ??
        true;
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('unregisterGlobalShortcut');
    await _activations.close();
  }
}
