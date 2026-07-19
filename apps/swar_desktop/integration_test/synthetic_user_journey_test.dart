// apps/swar_desktop/integration_test/synthetic_user_journey_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('synthetic user completes the Phase 1 desktop journey', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1405, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    binding.reportData = <String, dynamic>{
      'journey': 'phase-1-shell-synthetic-user',
      'platform': defaultTargetPlatform.name,
      'checks': <String>[],
    };

    await tester.pumpWidget(
      SwarApp(
        diagnosticsGateway: const _SyntheticDiagnosticsGateway(),
        dictationRepository: FakeDictationHistoryRepository(
          totalRecordCount: 60,
        ),
        insightsRepository: const FakeInsightsRepository(),
        dictationEngineGateway: const _UnavailableModelEngineGateway(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await _settle(tester);

    expect(find.byKey(const Key('swar-shell')), findsOneWidget);
    expect(find.text('Insights'), findsWidgets);
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
    expect(find.byKey(const Key('insights-pace-card')), findsOneWidget);
    _recordCheck(binding, 'SHELL-001 Insights is the default destination');
    await _captureFlutterSurface(binding, tester, 'shell-001-insights');
    _recordStep('opening dictation');

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    _recordStep('dictation tap dispatched');
    await _settle(tester);
    _recordStep('dictation transition settled');
    expect(find.byKey(const Key('dictation-list')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-0')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-9999')), findsNothing);
    _recordCheck(
      binding,
      'SHELL-001 Dictation opens with a lazy local-history list',
    );
    await _captureFlutterSurface(binding, tester, 'shell-002-dictation');

    await tester.enterText(find.byKey(const Key('dictation-search')), 'launch');
    await tester.pump();
    expect(find.textContaining('launch'), findsWidgets);
    expect(find.textContaining('customer call'), findsNothing);
    _recordCheck(
      binding,
      'SHELL-001 search narrows history through the repository',
    );
    await _captureFlutterSurface(binding, tester, 'shell-003-search-results');
    await _writeEvidence(binding);
  });
}

void _recordStep(String step) {
  // ignore: avoid_print
  print('SWAR_SYNTHETIC_STEP=$step');
}

final class _SyntheticDiagnosticsGateway implements CoreDiagnosticsGateway {
  const _SyntheticDiagnosticsGateway();

  @override
  String getCoreVersion() => 'synthetic-user';

  @override
  Stream<int> streamDemoEvents() => const Stream<int>.empty();
}

final class _UnavailableModelEngineGateway implements DictationEngineGateway {
  const _UnavailableModelEngineGateway();

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(finalText: '', insertionStatus: 'none');

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [];

  @override
  bool modelIsReady(String modelPath) => false;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  Future<bool> prepare(String modelPath) async => false;

  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/missing/offline-model.bin',
        installed: false,
        sizeBytes: 0,
      );

  @override
  Future<void> release() async {}

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      const Stream<DictationEngineEvent>.empty();
}

void _recordCheck(IntegrationTestWidgetsFlutterBinding binding, String check) {
  (binding.reportData!['checks']! as List<String>).add(check);
  // A host-visible checkpoint makes a stuck desktop journey diagnosable.
  // ignore: avoid_print
  print('SWAR_SYNTHETIC_CHECK=$check');
}

Future<void> _captureFlutterSurface(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) {
  expect(find.byKey(const Key('swar-app-capture-boundary')), findsOneWidget);
  final checkpoints =
      binding.reportData!.putIfAbsent(
            'visualCheckpoints',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  checkpoints.add(<String, dynamic>{
    'name': name,
    'width': tester.view.physicalSize.width,
    'height': tester.view.physicalSize.height,
  });
  return Future<void>.value();
}

Future<void> _writeEvidence(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final outputDirectory = Directory(
    '${Directory.systemTemp.path}/swar-synthetic-user-$pid',
  );
  await outputDirectory.create(recursive: true);

  final evidence = <String, dynamic>{...?binding.reportData};
  evidence['completedUtc'] = DateTime.now().toUtc().toIso8601String();
  const encoder = JsonEncoder.withIndent('  ');
  await File(
    '${outputDirectory.path}/report.json',
  ).writeAsString(encoder.convert(evidence));

  // The host runner copies this private temporary evidence only after the test passes.
  // ignore: avoid_print
  print('SWAR_SYNTHETIC_USER_EVIDENCE=${outputDirectory.path}');
}

Future<void> _settle(WidgetTester tester) async {
  // Swar intentionally has continuously scheduled recording affordances. A
  // synthetic user advances one deterministic frame for route/layout changes
  // without waiting for the entire app to become animation-free.
  await tester.pump(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
  );
}
