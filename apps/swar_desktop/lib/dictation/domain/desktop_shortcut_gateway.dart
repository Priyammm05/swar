abstract interface class DesktopShortcutGateway {
  Stream<void> get activations;

  Future<bool> initialize();

  Future<bool> requestInsertionPermission();

  Future<void> dispose();
}

final class NoopDesktopShortcutGateway implements DesktopShortcutGateway {
  const NoopDesktopShortcutGateway();

  @override
  Stream<void> get activations => const Stream.empty();

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> requestInsertionPermission() async => true;

  @override
  Future<void> dispose() async {}
}
