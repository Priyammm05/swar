// apps/swar_desktop/test/swar_shell_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/design_system/swar_components.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

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

    // The Insights grid renders every card without overflow at Wispr density;
    // the screen scrolls, so cards below the fold still build.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
    expect(find.byKey(const Key('insights-pace-card')), findsOneWidget);
    expect(find.byKey(const Key('insights-total-card')), findsOneWidget);
    expect(find.byKey(const Key('insights-streak-card')), findsOneWidget);
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

  testWidgets('native coordinator states drive the desktop overlay', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _EventDictationEngineGateway();
    final desktop = _RecordingDesktopShortcutGateway();
    await tester.pumpWidget(
      SwarApp(
        diagnosticsGateway: const _SilentDiagnosticsGateway(),
        dictationRepository: FakeDictationHistoryRepository(),
        insightsRepository: FakeInsightsRepository(),
        dictationEngineGateway: engine,
        desktopShortcutGateway: desktop,
        settingsRepository: InMemorySettingsRepository(
          initial: const SwarSettings(modelPath: '/test/model.bin'),
        ),
      ),
    );
    await tester.pump();

    desktop.emit(DesktopShortcutEventKind.toggle);
    await tester.pump();
    engine.emit(
      const DictationEngineEvent(
        sessionId: 'overlay-session',
        kind: DictationEngineEventKind.recording,
        previousState: DictationLifecycleState.preparing,
        currentState: DictationLifecycleState.recording,
        timestampMilliseconds: 1,
        reason: 'microphone ready',
      ),
    );
    await tester.pump();
    expect(desktop.lastState, DesktopOverlayState.recording);

    engine.emit(
      const DictationEngineEvent(
        sessionId: 'overlay-session',
        kind: DictationEngineEventKind.finalising,
        previousState: DictationLifecycleState.finalising,
        currentState: DictationLifecycleState.transcribing,
        timestampMilliseconds: 2,
        reason: 'audio drained',
      ),
    );
    await tester.pump();
    expect(desktop.lastState, DesktopOverlayState.finalising);
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
    expect(find.byKey(const Key('general-settings-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await tester.pumpAndSettle();

    final launchToggle = find.descendant(
      of: find.byKey(const Key('launch-at-login-setting')),
      matching: find.byType(SwarToggle),
    );
    await tester.tap(launchToggle);
    await tester.pump();

    // Leave Settings and return; the routed branch keeps its state, so the
    // change must persist without a modal to reopen.
    await tester.tap(find.byKey(const Key('top-insights-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();

    expect(tester.widget<SwarToggle>(launchToggle).value, isTrue);
  });

  testWidgets('settings test dictation explains the missing local model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
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

  testWidgets(
    'dictation stays locked until transcription and insertion finish',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engine = _BlockingFinishEngineGateway();
      await tester.pumpWidget(
        SwarApp(
          diagnosticsGateway: const _SilentDiagnosticsGateway(),
          dictationRepository: FakeDictationHistoryRepository(),
          insightsRepository: FakeInsightsRepository(),
          dictationEngineGateway: engine,
          settingsRepository: InMemorySettingsRepository(
            initial: const SwarSettings(modelPath: '/test/model.bin'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dictation is exercised through the Settings "Test dictation" control now
      // that the in-window Dictate button is gone.
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
      expect(find.text('Stop and transcribe'), findsOneWidget);

      await tester.tap(testButton);
      await tester.pump();
      expect(engine.finishCalls, 1);

      // While the finish is in flight the control is locked: tapping again must
      // not start or finish a second time.
      await tester.tap(testButton, warnIfMissed: false);
      await tester.pump();
      expect(engine.finishCalls, 1);

      engine.complete();
      await tester.pump();
      expect(find.text('Start test'), findsOneWidget);
      expect(engine.finishCalls, 1);
    },
  );
}

Widget _buildApp({FakeDictationHistoryRepository? dictations}) {
  return SwarApp(
    diagnosticsGateway: const _SilentDiagnosticsGateway(),
    dictationRepository: dictations ?? FakeDictationHistoryRepository(),
    insightsRepository: FakeInsightsRepository(),
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
  Future<bool> prepare(String modelPath) async => true;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  Future<void> release() async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(
        finalText: 'Test dictation',
        insertionStatus: 'copied',
      );

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [
    SwarMicrophone(
      id: 'default',
      name: 'Default microphone',
      isDefault: true,
      isBuiltIn: true,
    ),
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

final class _EventDictationEngineGateway implements DictationEngineGateway {
  final _events = StreamController<DictationEngineEvent>.broadcast();

  void emit(DictationEngineEvent event) => _events.add(event);

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(
        finalText: 'Done',
        insertionStatus: 'inserted',
      );

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [];

  @override
  bool modelIsReady(String modelPath) => true;

  @override
  Future<bool> prepare(String modelPath) async => true;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/test/model.bin',
        installed: true,
        sizeBytes: 1,
      );

  @override
  Future<void> release() async {
    await _events.close();
  }

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      _events.stream;
}

final class _RecordingDesktopShortcutGateway implements DesktopShortcutGateway {
  final _events = StreamController<DesktopShortcutEvent>.broadcast();
  DesktopOverlayState? lastState;

  void emit(DesktopShortcutEventKind kind) =>
      _events.add(DesktopShortcutEvent(kind));

  @override
  Stream<DesktopShortcutEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> hideOverlay() async => lastState = null;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> configureShortcut(String shortcutKey) async => true;

  @override
  Future<bool> requestInsertionPermission() async => true;

  @override
  Future<String> foregroundApplication() async => 'Test';

  @override
  Future<void> updateOverlay({
    required DesktopOverlayState state,
    required double audioLevel,
    required bool isLatched,
    required String shortcutKey,
  }) async => lastState = state;
}

final class _BlockingFinishEngineGateway implements DictationEngineGateway {
  final Completer<DictationEngineCompletion> _completion =
      Completer<DictationEngineCompletion>();
  int finishCalls = 0;

  void complete() => _completion.complete(
    const DictationEngineCompletion(
      finalText: 'Completed locally',
      insertionStatus: 'inserted',
    ),
  );

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<DictationEngineCompletion> finish(String sessionId) {
    finishCalls += 1;
    return _completion.future;
  }

  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [];

  @override
  bool modelIsReady(String modelPath) => modelPath.isNotEmpty;

  @override
  Future<bool> prepare(String modelPath) async => true;

  @override
  Future<void> prepareAudio(String microphoneId) async {}

  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/test/model.bin',
        installed: true,
        sizeBytes: 1,
      );

  @override
  Future<void> release() async {}

  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      Stream<DictationEngineEvent>.value(
        const DictationEngineEvent(
          sessionId: 'blocking-session',
          kind: DictationEngineEventKind.recording,
          previousState: DictationLifecycleState.preparing,
          currentState: DictationLifecycleState.recording,
          timestampMilliseconds: 1,
          reason: 'microphone ready',
        ),
      );
}
