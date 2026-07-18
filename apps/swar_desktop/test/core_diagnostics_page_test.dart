// apps/swar_desktop/test/core_diagnostics_page_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_card.dart';

void main() {
  testWidgets('checks the native core and renders streamed events', (
    tester,
  ) async {
    final gateway = _FakeCoreDiagnosticsGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoreDiagnosticsCard(gateway: gateway)),
      ),
    );

    expect(find.text('Offline engine'), findsOneWidget);
    expect(find.text('Run system check'), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-core-button')));
    await tester.pump();

    expect(find.text('Connected. Version 0.1.0-test'), findsOneWidget);

    gateway.addEvent(1);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await gateway.close();
  });
}

final class _FakeCoreDiagnosticsGateway implements CoreDiagnosticsGateway {
  final _events = StreamController<int>();

  @override
  String getCoreVersion() => '0.1.0-test';

  @override
  Stream<int> streamDemoEvents() => _events.stream;

  void addEvent(int event) => _events.add(event);

  Future<void> close() => _events.close();
}
