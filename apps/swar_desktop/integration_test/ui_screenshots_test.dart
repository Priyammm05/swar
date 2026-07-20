// apps/swar_desktop/integration_test/ui_screenshots_test.dart
//
// Developer harness: renders the real app (real fonts + SVG logo) at desktop
// size and writes a PNG of each screen so the UI can be compared against the
// design mockups. Not part of the product test suite — run explicitly:
//   flutter test integration_test/ui_screenshots_test.dart -d macos
// PNGs land in the directory named by SWAR_SHOT_DIR (defaults to the system
// temp dir); the path is printed as SWAR_SHOT=<path> for each capture.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture every screen to PNG', (tester) async {
    tester.view
      ..physicalSize = const Size(2160, 3200)
      ..devicePixelRatio = 2;
    // Force light so the captures match the light-mode design mockups.
    tester.platformDispatcher.platformBrightnessTestValue = ui.Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SwarApp(
        diagnosticsGateway: const _ShotDiagnostics(),
        dictationRepository: FakeDictationHistoryRepository(
          totalRecordCount: 60,
        ),
        insightsRepository: FakeInsightsRepository(),
        dictationEngineGateway: const _ShotEngine(),
        settingsRepository: InMemorySettingsRepository(
          initial: const SwarSettings(
            modelPath:
                '/Users/you/Library/Application Support/dev.Swar.Swar/models/ggml-small-q5_1.bin',
            microphoneId: 'built-in',
            launchAtLogin: true,
            showSwarBar: true,
            showInDock: true,
            keepModelsWarm: true,
          ),
        ),
      ),
    );
    await _settle(tester);

    await _waitFor(tester, find.byKey(const Key('insights-grid')));
    await _shot(tester, 'insights');

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await _waitFor(tester, find.byKey(const Key('dictation-list')));
    await _shot(tester, 'activity');

    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await _waitFor(tester, find.byKey(const Key('general-settings-page')));
    await _shot(tester, 'settings-general');

    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await _waitFor(tester, find.byKey(const Key('system-settings-page')));
    await _shot(tester, 'settings-system');
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  await _settle(tester);
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(const Key('swar-app-capture-boundary')))
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return;
  final dir =
      Platform.environment['SWAR_SHOT_DIR'] ?? Directory.systemTemp.path;
  await Directory(dir).create(recursive: true);
  final file = File('$dir/$name.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  // ignore: avoid_print
  print('SWAR_SHOT=${file.path}');
}

final class _ShotDiagnostics implements CoreDiagnosticsGateway {
  const _ShotDiagnostics();
  @override
  String getCoreVersion() => 'screenshot';
  @override
  Stream<int> streamDemoEvents() => const Stream<int>.empty();
}

final class _ShotEngine implements DictationEngineGateway {
  const _ShotEngine();
  @override
  Future<void> cancel(String sessionId) async {}
  @override
  Future<DictationEngineCompletion> finish(String sessionId) async =>
      const DictationEngineCompletion(
        finalText: 'Screenshot',
        insertionStatus: 'inserted',
      );
  @override
  Future<OfflineModelInstallation> installRecommendedModel() async =>
      recommendedModelStatus();

  @override
  OfflineModelInstallation indicPackStatus() => const OfflineModelInstallation(
    path: '/test/indic-conformer',
    installed: false,
    sizeBytes: 0,
  );

  @override
  Future<OfflineModelInstallation> installIndicModels() async =>
      indicPackStatus();
  @override
  Future<List<SwarMicrophone>> listMicrophones() async => const [
    SwarMicrophone(
      id: 'built-in',
      name: 'MacBook Pro Microphone',
      isDefault: true,
      isBuiltIn: true,
    ),
  ];
  @override
  bool modelIsReady(String modelPath) => modelPath.isNotEmpty;
  @override
  Future<void> prepareAudio(String microphoneId) async {}
  @override
  Future<bool> prepare(String modelPath) async => true;
  @override
  OfflineModelInstallation recommendedModelStatus() =>
      const OfflineModelInstallation(
        path: '/models/ggml-small-q5_1.bin',
        installed: true,
        sizeBytes: 181000000,
      );
  @override
  Future<void> release() async {}
  @override
  Stream<DictationEngineEvent> start(DictationEngineConfig config) =>
      const Stream<DictationEngineEvent>.empty();
}
