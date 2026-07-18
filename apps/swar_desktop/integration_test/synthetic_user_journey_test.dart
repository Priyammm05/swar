// apps/swar_desktop/integration_test/synthetic_user_journey_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/data/rust_core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/data/rust_dictation_engine_gateway.dart';
import 'package:swar_desktop/generated_bridge/frb_generated.dart';
import 'package:swar_desktop/insights/data/fake_insights_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('synthetic user completes the Phase 1 desktop journey', (
    tester,
  ) async {
    await RustLib.init();
    addTearDown(RustLib.dispose);

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
        diagnosticsGateway: RustCoreDiagnosticsGateway(),
        dictationRepository: FakeDictationHistoryRepository(),
        insightsRepository: const FakeInsightsRepository(),
        dictationEngineGateway: RustDictationEngineGateway(),
        settingsRepository: InMemorySettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('swar-shell')), findsOneWidget);
    expect(find.text('Insights'), findsWidgets);
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
    expect(find.byKey(const Key('insights-pace-card')), findsOneWidget);
    _recordCheck(binding, 'SHELL-001 Insights is the default destination');
    await _captureFlutterSurface(binding, tester, 'shell-001-insights');

    tester.view.physicalSize = const Size(1405, 760);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('top-dictation-nav')));
    await tester.pumpAndSettle();
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
    await tester.enterText(find.byKey(const Key('dictation-search')), '');
    await tester.pump();

    tester.view.physicalSize = const Size(620, 700);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compact-navigation')), findsOneWidget);
    expect(find.byKey(const Key('top-dictation-nav')), findsNothing);
    _recordCheck(binding, 'SHELL-002 compact navigation replaces the sidebar');
    await _captureFlutterSurface(binding, tester, 'shell-002-compact');

    await tester.tap(find.byKey(const Key('compact-insights-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
    expect(find.text('Desktop usage'), findsOneWidget);
    _recordCheck(
      binding,
      'SHELL-002 Insights is reachable from compact navigation',
    );

    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-navigation')), findsOneWidget);

    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(find.byKey(const Key('general-settings-page')), findsOneWidget);
    expect(find.byKey(const Key('writing-mode-setting')), findsOneWidget);
    _recordCheck(
      binding,
      'SHELL-002 General settings opens from the persistent shell',
    );

    final testDictation = find.byKey(const Key('test-dictation-button'));
    await tester.scrollUntilVisible(
      testDictation,
      260,
      scrollable: find.descendant(
        of: find.byKey(const Key('general-settings-scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.tap(testDictation);
    await tester.pump();
    expect(
      find.text('Choose an offline Whisper model before testing dictation.'),
      findsOneWidget,
    );
    _recordCheck(
      binding,
      'DICTATION-001 missing offline model is explained before microphone capture',
    );

    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('system-settings-page')), findsOneWidget);
    final launchAtLogin = find.byKey(const Key('launch-at-login-setting'));
    await tester.ensureVisible(launchAtLogin);
    await tester.pumpAndSettle();
    await tester.tap(launchAtLogin);
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-settings-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-system-nav')));
    await tester.pumpAndSettle();
    final launchSetting = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const Key('launch-at-login-setting')),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(launchSetting.value, isTrue);
    _recordCheck(binding, 'SHELL-003 mock settings persist across navigation');

    final checkButton = find.byKey(const Key('check-core-button'));
    await tester.scrollUntilVisible(
      checkButton,
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('system-settings-scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
    final buttonSemantics = tester.getSemantics(checkButton);
    expect(buttonSemantics.label, contains('Run system check'));
    expect(buttonSemantics.flagsCollection.isButton, isTrue);
    expect(buttonSemantics.flagsCollection.isEnabled, isTrue);
    _recordCheck(
      binding,
      'SHELL-003 system check remains accessible under System',
    );
    await _captureFlutterSurface(binding, tester, 'shell-005-system');

    await tester.tap(checkButton);
    final firstRunElapsed = await _pumpUntilFound(
      tester,
      find.byKey(const Key('core-event-5')),
      timeout: const Duration(seconds: 5),
    );

    expect(find.text('Connected. Version 0.1.0'), findsOneWidget);
    for (var event = 1; event <= 5; event++) {
      expect(find.byKey(Key('core-event-$event')), findsOneWidget);
    }
    expect(firstRunElapsed, lessThan(const Duration(seconds: 5)));
    _recordCheck(
      binding,
      'SHELL-003 real native stream completed in '
      '${firstRunElapsed.inMilliseconds} ms of foreground interaction time',
    );
    await _captureFlutterSurface(binding, tester, 'shell-006-core-connected');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Connected. Version 0.1.0'), findsOneWidget);
    expect(find.byKey(const Key('core-event-5')), findsOneWidget);
    _recordCheck(
      binding,
      'SHELL-003 visible state survives inactive and resumed lifecycle',
    );

    await tester.ensureVisible(checkButton);
    await tester.tap(checkButton);
    await _pumpUntilAbsent(
      tester,
      find.byKey(const Key('core-event-5')),
      timeout: const Duration(seconds: 2),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('core-event-5')),
      timeout: const Duration(seconds: 5),
    );

    for (var event = 1; event <= 5; event++) {
      expect(find.byKey(Key('core-event-$event')), findsOneWidget);
    }
    expect(find.text('The native core could not be reached.'), findsNothing);
    expect(
      find.text('The native event stream stopped unexpectedly.'),
      findsNothing,
    );
    _recordCheck(
      binding,
      'SHELL-003 repeated system check replaces stale state and succeeds',
    );
    await _captureFlutterSurface(binding, tester, 'shell-006-repeat-complete');
    await _writeEvidence(binding);
  });
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
) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('swar-app-capture-boundary')),
  );
  final image = await boundary.toImage().timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw TestFailure('Screenshot $name did not render.'),
  );
  final byteData = await image
      .toByteData(format: ui.ImageByteFormat.png)
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TestFailure('Screenshot $name did not encode.'),
      );
  image.dispose();

  expect(byteData, isNotNull);
  final screenshots =
      binding.reportData!.putIfAbsent(
            'screenshots',
            () => <Map<String, dynamic>>[],
          )
          as List<Map<String, dynamic>>;
  screenshots.add(<String, dynamic>{
    'screenshotName': name,
    'bytes': byteData!.buffer.asUint8List().toList(growable: false),
  });
}

Future<void> _writeEvidence(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final outputDirectory = Directory(
    '${Directory.systemTemp.path}/swar-synthetic-user-$pid',
  );
  await outputDirectory.create(recursive: true);

  final evidence = <String, dynamic>{...?binding.reportData};
  final screenshots =
      (evidence.remove('screenshots') as List<dynamic>?) ?? const <dynamic>[];
  final screenshotNames = <String>[];

  for (final screenshot in screenshots.cast<Map<String, dynamic>>()) {
    final name = screenshot['screenshotName']! as String;
    final bytes = (screenshot['bytes']! as List<dynamic>).cast<int>();
    await File('${outputDirectory.path}/$name.png').writeAsBytes(bytes);
    screenshotNames.add('$name.png');
  }

  evidence['screenshots'] = screenshotNames;
  evidence['completedUtc'] = DateTime.now().toUtc().toIso8601String();
  const encoder = JsonEncoder.withIndent('  ');
  await File(
    '${outputDirectory.path}/report.json',
  ).writeAsString(encoder.convert(evidence));

  // The host runner copies this private temporary evidence only after the test passes.
  // ignore: avoid_print
  print('SWAR_SYNTHETIC_USER_EVIDENCE=${outputDirectory.path}');
}

Future<Duration> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  const interval = Duration(milliseconds: 50);
  var elapsed = Duration.zero;

  while (finder.evaluate().isEmpty && elapsed < timeout) {
    await tester.pump(interval);
    elapsed += interval;
  }

  expect(
    finder,
    findsOneWidget,
    reason: 'The expected user-visible state did not appear within $timeout.',
  );
  return elapsed;
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  const interval = Duration(milliseconds: 50);
  var elapsed = Duration.zero;

  while (finder.evaluate().isNotEmpty && elapsed < timeout) {
    await tester.pump(interval);
    elapsed += interval;
  }

  expect(
    finder,
    findsNothing,
    reason: 'The stale user-visible state did not clear within $timeout.',
  );
}
