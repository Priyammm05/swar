enum DesktopShortcutEventKind { pressed, released, toggle, stop, cancel }

final class DesktopShortcutEvent {
  const DesktopShortcutEvent(this.kind);

  final DesktopShortcutEventKind kind;
}

enum DesktopOverlayState { idle, preparing, recording, finalising }

abstract interface class DesktopShortcutGateway {
  Stream<DesktopShortcutEvent> get events;

  Future<bool> initialize();

  Future<bool> configureShortcut(String shortcutKey);

  Future<bool> requestInsertionPermission();

  Future<String> foregroundApplication();

  /// Whether the currently focused field is a secure/password field. Used to
  /// suppress history storage for that dictation (privacy P0).
  Future<bool> focusedFieldIsSecure();

  Future<void> updateOverlay({
    required DesktopOverlayState state,
    required double audioLevel,
    required bool isLatched,
    required String shortcutKey,
  });

  Future<void> hideOverlay();

  Future<void> dispose();
}

final class NoopDesktopShortcutGateway implements DesktopShortcutGateway {
  const NoopDesktopShortcutGateway();

  @override
  Stream<DesktopShortcutEvent> get events => const Stream.empty();

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> configureShortcut(String shortcutKey) async => false;

  @override
  Future<bool> requestInsertionPermission() async => true;

  @override
  Future<String> foregroundApplication() async => '';

  @override
  Future<bool> focusedFieldIsSecure() async => false;

  @override
  Future<void> updateOverlay({
    required DesktopOverlayState state,
    required double audioLevel,
    required bool isLatched,
    required String shortcutKey,
  }) async {}

  @override
  Future<void> hideOverlay() async {}

  @override
  Future<void> dispose() async {}
}
