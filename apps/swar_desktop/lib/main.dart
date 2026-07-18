// apps/swar_desktop/lib/main.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/data/rust_core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/rust_dictation_history_repository.dart';
import 'package:swar_desktop/dictation/data/rust_dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/data/platform_desktop_shortcut_gateway.dart';
import 'package:swar_desktop/generated_bridge/api/history.dart';
import 'package:swar_desktop/generated_bridge/frb_generated.dart';
import 'package:swar_desktop/insights/data/rust_insights_repository.dart';
import 'package:swar_desktop/settings/data/rust_settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await initializeLocalStore();

  runApp(
    SwarApp(
      diagnosticsGateway: RustCoreDiagnosticsGateway(),
      dictationRepository: RustDictationHistoryRepository(),
      insightsRepository: RustInsightsRepository(),
      dictationEngineGateway: RustDictationEngineGateway(),
      desktopShortcutGateway: PlatformDesktopShortcutGateway(),
      settingsRepository: RustSettingsRepository(),
    ),
  );
}
