// apps/swar_desktop/integration_test/core_bridge_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swar_desktop/generated_bridge/api/diagnostics.dart';
import 'package:swar_desktop/generated_bridge/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('calls Rust and receives its worker-thread event stream', (
    tester,
  ) async {
    await RustLib.init();
    addTearDown(RustLib.dispose);

    expect(getCoreVersion(), '0.1.0');

    final events = await streamDemoEvents()
        .take(5)
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(events, [1, 2, 3, 4, 5]);
  });
}
