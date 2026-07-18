// apps/swar_desktop/lib/app/swar_app.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_router.dart';
import 'package:swar_desktop/design_system/swar_theme.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

/// Application root. Presentation Layer.
class SwarApp extends StatefulWidget {
  const SwarApp({
    required this.diagnosticsGateway,
    required this.dictationRepository,
    required this.settingsRepository,
    super.key,
  });

  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationHistoryRepository dictationRepository;
  final SettingsRepository settingsRepository;

  @override
  State<SwarApp> createState() => _SwarAppState();
}

final class _SwarAppState extends State<SwarApp> {
  late final SettingsViewModel _settingsViewModel;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _settingsViewModel = SettingsViewModel(
      repository: widget.settingsRepository,
    );
    _router = createSwarRouter(
      dictationRepository: widget.dictationRepository,
      settingsViewModel: _settingsViewModel,
      diagnosticsGateway: widget.diagnosticsGateway,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _settingsViewModel.dispose();
    super.dispose();
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
