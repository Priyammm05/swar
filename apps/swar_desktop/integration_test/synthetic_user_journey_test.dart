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
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('synthetic user completes the local desktop journey', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1405, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    binding.reportData = <String, dynamic>{
      'journey': 'local-dictation-synthetic-user',
      'platform': defaultTargetPlatform.name,
      'checks': <String>[],
    };

    final history = _TrackingHistoryRepository(totalRecordCount: 60);
    final engine = _SyntheticDictationEngineGateway();
    final settings = InMemorySettingsRepository(
      initial: const SwarSettings(
        modelPath: '/synthetic/offline-model.bin',
        microphoneId: 'built-in',
      ),
    );
    await tester.pumpWidget(
      SwarApp(
        diagnosticsGateway: const _SyntheticDiagnosticsGateway(),
        dictationRepository: history,
        insightsRepository: const FakeInsightsRepository(),
        dictationEngineGateway: engine,
        settingsRepository: settings,
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
    await _pumpUntilFound(tester, find.byKey(const Key('dictation-list')));
    _recordStep('dictation transition settled');
    expect(find.byKey(const Key('dictation-list')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-0')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-9999')), findsNothing);
    expect(find.byKey(const Key('dictation-show-more')), findsOneWidget);
    _recordCheck(
      binding,
      'SHELL-001 Dictation opens with a lazy local-history list',
    );
    await _captureFlutterSurface(binding, tester, 'shell-002-dictation');

    await tester.tap(find.byKey(const Key('dictation-show-more')));
    await _settle(tester);
    await _pumpUntilGone(tester, find.byKey(const Key('dictation-show-more')));
    expect(find.byKey(const Key('dictation-show-more')), findsNothing);
    expect(history.requestedOffsets, containsAllInOrder(<int>[0, 50]));
    _recordCheck(
      binding,
      'DICTATION-001 history loads fifty rows and then the remaining page',
    );

    await tester.enterText(find.byKey(const Key('dictation-search')), 'launch');
    await tester.pump();
    await _pumpUntilGone(tester, find.textContaining('customer call'));
    expect(find.textContaining('launch'), findsWidgets);
    expect(find.textContaining('customer call'), findsNothing);
    _recordCheck(
      binding,
      'SHELL-001 search narrows history through the repository',
    );
    await _captureFlutterSurface(binding, tester, 'shell-003-search-results');

    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await _settle(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('general-settings-page')),
    );
    expect(find.byKey(const Key('general-settings-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await _settle(tester);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('launch-at-login-setting')),
    );
    await tester.tap(find.byKey(const Key('launch-at-login-setting')));
    await _settle(tester);
    // Settings is a routed screen now: leave to Activity and return; the branch
    // keeps its state, so the change persists with no modal to reopen.
    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await _settle(tester);
    expect(settings.read().launchAtLogin, isTrue);
    _recordCheck(
      binding,
      'SHELL-003 system settings persist across navigation',
    );

    tester.view.physicalSize = const Size(620, 700);
    await _settle(tester);
    await _pumpUntilFound(tester, find.byKey(const Key('compact-navigation')));
    expect(find.byKey(const Key('compact-navigation')), findsOneWidget);
    expect(find.byKey(const Key('top-dictation-nav')), findsNothing);
    _recordCheck(
      binding,
      'SHELL-002 compact navigation keeps Dictation, Insights, and Settings reachable',
    );
    await _captureFlutterSurface(binding, tester, 'shell-004-compact');
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

final class _SyntheticDictationEngineGateway implements DictationEngineGateway {
  int finishCalls = 0;

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async {
    finishCalls += 1;
    return const DictationEngineCompletion(
      finalText: 'Synthetic local dictation',
      insertionStatus: 'inserted',
    );
  }

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [];

  @override
  bool modelIsReady(String modelPath) => modelPath.isNotEmpty;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  Future<bool> prepare(String modelPath) async => true;

  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/synthetic/offline-model.bin',
        installed: true,
        sizeBytes: 1,
      );

  @override
  Future<void> release() async {}

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      Stream<DictationEngineEvent>.value(
        const DictationEngineEvent(
          sessionId: 'synthetic-session',
          kind: DictationEngineEventKind.recording,
          previousState: DictationLifecycleState.preparing,
          currentState: DictationLifecycleState.recording,
          timestampMilliseconds: 1,
          reason: 'microphone ready',
        ),
      );
}

final class _TrackingHistoryRepository implements DictationHistoryRepository {
  _TrackingHistoryRepository({required int totalRecordCount})
    : _delegate = FakeDictationHistoryRepository(
        totalRecordCount: totalRecordCount,
      );

  final FakeDictationHistoryRepository _delegate;
  final List<int> requestedOffsets = <int>[];
  int loadCalls = 0;

  @override
  Future<bool> correctDictation({
    required String id,
    required String correctedText,
    required bool learningOptedIn,
  }) => _delegate.correctDictation(
    id: id,
    correctedText: correctedText,
    learningOptedIn: learningOptedIn,
  );

  @override
  Future<DictationHistoryPage> loadPage(
    DictationQuery query, {
    required int offset,
    required int limit,
  }) {
    loadCalls += 1;
    requestedOffsets.add(offset);
    return _delegate.loadPage(query, offset: offset, limit: limit);
  }
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

// Swar cannot use pumpAndSettle because it schedules continuous recording
// affordances, so async work (history paging, search, lifecycle transitions)
// is drained by advancing bounded deterministic frames until a condition holds.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 60,
}) async {
  for (var frame = 0; frame < maxFrames && !condition(); frame++) {
    await _settle(tester);
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty);

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isEmpty);

Future<void> _settle(WidgetTester tester) async {
  // Swar intentionally has continuously scheduled recording affordances. A
  // synthetic user advances one deterministic frame for route/layout changes
  // without waiting for the entire app to become animation-free.
  await tester.pump(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
  );
}
