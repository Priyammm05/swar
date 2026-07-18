// apps/swar_desktop/test/core_diagnostics_view_model_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_state.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_view_model.dart';

void main() {
  test('loads version and appends native events', () async {
    final gateway = _FakeGateway();
    final viewModel = CoreDiagnosticsViewModel(gateway: gateway);

    await viewModel.checkCore();
    gateway.events.add(3);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.state.status, CoreConnectionStatus.ready);
    expect(viewModel.state.version, '0.1.0-test');
    expect(viewModel.state.events, [3]);

    viewModel.dispose();
    await gateway.events.close();
  });
}

final class _FakeGateway implements CoreDiagnosticsGateway {
  final events = StreamController<int>();

  @override
  String getCoreVersion() => '0.1.0-test';

  @override
  Stream<int> streamDemoEvents() => events.stream;
}
