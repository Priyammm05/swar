// apps/swar_desktop/test/swar_shell_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';

void main() {
  testWidgets('wide shell opens Insights first and navigates to Dictation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
    expect(find.byKey(const Key('insights-pace-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dictation-list')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-0')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-9999')), findsNothing);
  });

  testWidgets('Insights fits a short desktop window at Wispr density', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1405, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    final paceCard = find.byKey(const Key('insights-pace-card'));
    final totalCard = find.byKey(const Key('insights-total-card'));
    final streakCard = find.byKey(const Key('insights-streak-card'));

    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(streakCard).dy, lessThanOrEqualTo(760));
    expect(
      tester.getSize(totalCard).width,
      closeTo(tester.getSize(paceCard).width * 2, 1),
    );
  });

  testWidgets('compact shell uses bottom navigation without layout errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-navigation')), findsOneWidget);
    expect(find.byKey(const Key('top-dictation-nav')), findsNothing);

    expect(find.byKey(const Key('insights-grid')), findsOneWidget);

    await tester.tap(find.byKey(const Key('compact-dictation-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dictation-list')), findsOneWidget);
  });

  testWidgets('settings repository preserves changes across navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(find.byKey(const Key('general-settings-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('launch-at-login-setting')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-insights-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await tester.pumpAndSettle();

    final setting = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const Key('launch-at-login-setting')),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(setting.value, isTrue);
  });

  testWidgets('settings test dictation explains the missing local model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();
    final testButton = find.byKey(const Key('test-dictation-button'));
    await tester.scrollUntilVisible(
      testButton,
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('general-settings-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(testButton);
    await tester.pump();

    expect(
      find.text('Choose an offline Whisper model before testing dictation.'),
      findsOneWidget,
    );
  });

  testWidgets('empty history explains what will appear', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _buildApp(
        dictations: FakeDictationHistoryRepository(totalRecordCount: 0),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await tester.pumpAndSettle();

    expect(find.text('Your dictations will appear here'), findsOneWidget);
    expect(find.byKey(const Key('dictation-list')), findsNothing);
  });

  testWidgets('search is delegated to the history repository', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('dictation-search')), 'launch');
    await tester.pump();

    expect(find.textContaining('launch'), findsWidgets);
    expect(find.textContaining('customer call'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('dictation-search')),
      'not in sample history',
    );
    await tester.pump();
    expect(find.text('No matching dictations'), findsOneWidget);
  });
}

Widget _buildApp({FakeDictationHistoryRepository? dictations}) {
  return SwarApp(
    diagnosticsGateway: const _SilentDiagnosticsGateway(),
    dictationRepository: dictations ?? FakeDictationHistoryRepository(),
    insightsRepository: const FakeInsightsRepository(),
    dictationEngineGateway: const _FakeDictationEngineGateway(),
    settingsRepository: InMemorySettingsRepository(),
  );
}

final class _SilentDiagnosticsGateway implements CoreDiagnosticsGateway {
  const _SilentDiagnosticsGateway();

  @override
  String getCoreVersion() => '0.1.0-test';

  @override
  Stream<int> streamDemoEvents() => const Stream<int>.empty();
}

final class _FakeDictationEngineGateway implements DictationEngineGateway {
  const _FakeDictationEngineGateway();

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(
        finalText: 'Test dictation',
        insertionStatus: 'copied',
      );

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [
    SwarMicrophone(id: 'default', name: 'Default microphone', isDefault: true),
  ];

  @override
  bool modelIsReady(String modelPath) => modelPath == '/test/model.bin';

  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/test/model.bin',
        installed: true,
        sizeBytes: 142000000,
      );

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      const Stream<DictationEngineEvent>.empty();
}
