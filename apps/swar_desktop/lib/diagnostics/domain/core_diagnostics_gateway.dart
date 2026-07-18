// apps/swar_desktop/lib/diagnostics/domain/core_diagnostics_gateway.dart

/// Contract between Flutter and Swar's native core. Domain Layer.
abstract interface class CoreDiagnosticsGateway {
  String getCoreVersion();

  Stream<int> streamDemoEvents();
}
