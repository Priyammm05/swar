// apps/swar_desktop/test/swar_shell_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';

void main() {
  testWidgets('wide shell navigates between the four approved pages', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dictation-list')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-0')), findsOneWidget);
    expect(find.byKey(const Key('dictation-record-9999')), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar-insights-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-settings-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('general-settings-page')), findsOneWidget);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('system-settings-page')), findsOneWidget);
  });

  testWidgets('compact shell uses bottom navigation without layout errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(620, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-navigation')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-dictation-nav')), findsNothing);

    await tester.tap(find.byKey(const Key('compact-insights-nav')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-grid')), findsOneWidget);
  });

  testWidgets('settings repository preserves changes across navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar-settings-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('launch-at-login-setting')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-insights-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-settings-nav')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    final setting = tester.widget<SwitchListTile>(
      find.byKey(const Key('launch-at-login-setting')),
    );
    expect(setting.value, isTrue);
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

    expect(find.text('Your dictations will appear here'), findsOneWidget);
    expect(find.byKey(const Key('dictation-list')), findsNothing);
  });

  testWidgets('search is delegated to the history repository', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildApp());
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
