// apps/swar_desktop/lib/diagnostics/data/rust_core_diagnostics_gateway.dart

import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/generated_bridge/api/diagnostics.dart' as rust;

/// Rust-backed diagnostics implementation. Data Layer.
final class RustCoreDiagnosticsGateway implements CoreDiagnosticsGateway {
  @override
  String getCoreVersion() => rust.getCoreVersion();

  @override
  Stream<int> streamDemoEvents() => rust.streamDemoEvents();
}
