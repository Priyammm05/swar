// apps/swar_desktop/lib/main.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/app/swar_app.dart';
import 'package:swar_desktop/diagnostics/data/rust_core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/data/fake_dictation_history_repository.dart';
import 'package:swar_desktop/generated_bridge/frb_generated.dart';
import 'package:swar_desktop/settings/data/in_memory_settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  runApp(
    SwarApp(
      diagnosticsGateway: RustCoreDiagnosticsGateway(),
      dictationRepository: FakeDictationHistoryRepository(),
      settingsRepository: InMemorySettingsRepository(),
    ),
  );
}
