// apps/swar_desktop/lib/app/swar_app.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_router.dart';
import 'package:swar_desktop/design_system/swar_theme.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

/// Application root. Presentation Layer.
class SwarApp extends StatefulWidget {
  const SwarApp({
    required this.diagnosticsGateway,
    required this.dictationRepository,
    required this.insightsRepository,
    required this.dictationEngineGateway,
    required this.settingsRepository,
    this.desktopShortcutGateway = const NoopDesktopShortcutGateway(),
    super.key,
  });

  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationHistoryRepository dictationRepository;
  final InsightsRepository insightsRepository;
  final DictationEngineGateway dictationEngineGateway;
  final SettingsRepository settingsRepository;
  final DesktopShortcutGateway desktopShortcutGateway;

  @override
  State<SwarApp> createState() => _SwarAppState();
}

final class _SwarAppState extends State<SwarApp> {
  late final SettingsViewModel _settingsViewModel;
  late final DictationSessionViewModel _dictationSessionViewModel;
  late final GoRouter _router;
  StreamSubscription<void>? _shortcutSubscription;

  @override
  void initState() {
    super.initState();
    _settingsViewModel = SettingsViewModel(
      repository: widget.settingsRepository,
    );
    _dictationSessionViewModel = DictationSessionViewModel(
      gateway: widget.dictationEngineGateway,
    );
    _shortcutSubscription = widget.desktopShortcutGateway.activations.listen(
      (_) => _toggleDictation(),
    );
    unawaited(widget.desktopShortcutGateway.initialize());
    _router = createSwarRouter(
      dictationRepository: widget.dictationRepository,
      insightsRepository: widget.insightsRepository,
      settingsViewModel: _settingsViewModel,
      diagnosticsGateway: widget.diagnosticsGateway,
      dictationSessionViewModel: _dictationSessionViewModel,
    );
  }

  @override
  void dispose() {
    _shortcutSubscription?.cancel();
    unawaited(widget.desktopShortcutGateway.dispose());
    _router.dispose();
    _settingsViewModel.dispose();
    _dictationSessionViewModel.dispose();
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_dictationSessionViewModel.isRecording) {
      await _dictationSessionViewModel.finish();
      return;
    }
    if (_dictationSessionViewModel.state == DictationSessionState.finalising ||
        _dictationSessionViewModel.state == DictationSessionState.preparing) {
      return;
    }
    final settings = _settingsViewModel.settings;
    if (settings.pasteAutomatically) {
      await widget.desktopShortcutGateway.requestInsertionPermission();
    }
    await _dictationSessionViewModel.start(
      DictationEngineConfig(
        modelPath: settings.modelPath,
        language: settings.language.name,
        writingMode: settings.writingMode.name,
        pasteAutomatically: settings.pasteAutomatically,
        restoreClipboard: settings.restoreClipboard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'swar',
      theme: SwarTheme.light(),
      routerConfig: _router,
      builder: (context, child) => RepaintBoundary(
        key: const Key('swar-app-capture-boundary'),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
