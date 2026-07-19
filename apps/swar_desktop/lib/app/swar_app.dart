// apps/swar_desktop/lib/app/swar_app.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_router.dart';
import 'package:swar_desktop/design_system/swar_theme.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/application/dictation_activation_controller.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_engine_gateway.dart';
import 'package:swar_desktop/dictation/domain/desktop_shortcut_gateway.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/domain/personalization_repository.dart';
import 'package:swar_desktop/settings/data/in_memory_personalization_repository.dart';
import 'package:swar_desktop/settings/presentation/personalization_view_model.dart';
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
    this.personalizationRepository,
    super.key,
  });

  final CoreDiagnosticsGateway diagnosticsGateway;
  final DictationHistoryRepository dictationRepository;
  final InsightsRepository insightsRepository;
  final DictationEngineGateway dictationEngineGateway;
  final SettingsRepository settingsRepository;
  final DesktopShortcutGateway desktopShortcutGateway;
  final PersonalizationRepository? personalizationRepository;

  @override
  State<SwarApp> createState() => _SwarAppState();
}

final class _SwarAppState extends State<SwarApp> {
  late final SettingsViewModel _settingsViewModel;
  late final DictationSessionViewModel _dictationSessionViewModel;
  late final GoRouter _router;
  late final DictationActivationController _activationController;
  late final PersonalizationViewModel _personalizationViewModel;
  StreamSubscription<DesktopShortcutEvent>? _shortcutSubscription;
  String? _configuredShortcut;
  String? _preparedMicrophone;

  @override
  void initState() {
    super.initState();
    _settingsViewModel = SettingsViewModel(
      repository: widget.settingsRepository,
    );
    _dictationSessionViewModel = DictationSessionViewModel(
      gateway: widget.dictationEngineGateway,
    );
    _personalizationViewModel = PersonalizationViewModel(
      repository:
          widget.personalizationRepository ??
          InMemoryPersonalizationRepository(),
    )..load();
    _activationController = DictationActivationController(
      start: _startDictation,
      finish: _dictationSessionViewModel.finish,
      cancel: _dictationSessionViewModel.cancel,
      modeChanged: _syncOverlay,
    );
    _dictationSessionViewModel.addListener(_syncOverlay);
    _settingsViewModel.addListener(_settingsChanged);
    unawaited(
      _dictationSessionViewModel.prepare(_settingsViewModel.settings.modelPath),
    );
    unawaited(_prepareAudioIfNeeded());
    _shortcutSubscription = widget.desktopShortcutGateway.events.listen(
      (event) => unawaited(_activationController.handle(event)),
    );
    unawaited(
      widget.desktopShortcutGateway.initialize().then((_) async {
        await _configureShortcutIfNeeded();
        _syncOverlay();
      }),
    );
    _router = createSwarRouter(
      dictationRepository: widget.dictationRepository,
      insightsRepository: widget.insightsRepository,
      settingsViewModel: _settingsViewModel,
      diagnosticsGateway: widget.diagnosticsGateway,
      dictationSessionViewModel: _dictationSessionViewModel,
      personalizationViewModel: _personalizationViewModel,
    );
  }

  @override
  void dispose() {
    _shortcutSubscription?.cancel();
    _dictationSessionViewModel.removeListener(_syncOverlay);
    _settingsViewModel.removeListener(_settingsChanged);
    _activationController.dispose();
    unawaited(widget.desktopShortcutGateway.dispose());
    _router.dispose();
    _settingsViewModel.dispose();
    _dictationSessionViewModel.dispose();
    _personalizationViewModel.dispose();
    unawaited(widget.dictationEngineGateway.release());
    super.dispose();
  }

  Future<bool> _startDictation() async {
    final settings = _settingsViewModel.settings;
    final foregroundApplication = await widget.desktopShortcutGateway
        .foregroundApplication();
    final excluded = settings.excludedApplications.any(
      (value) => value.toLowerCase() == foregroundApplication.toLowerCase(),
    );
    if (settings.pasteAutomatically) {
      await widget.desktopShortcutGateway.requestInsertionPermission();
    }
    await _dictationSessionViewModel.start(
      DictationEngineConfig(
        modelPath: settings.modelPath,
        microphoneId: settings.microphoneId,
        language: settings.language.name,
        writingMode: settings.writingMode.name,
        pasteAutomatically: settings.pasteAutomatically,
        restoreClipboard: settings.restoreClipboard,
        keepModelsWarm: settings.keepModelsWarm,
        enableLivePreview: true,
        sourceApplication: excluded ? '' : foregroundApplication,
        enhancementProvider: settings.enhancementProvider.name,
        providerEndpoint: settings.providerEndpoint,
        providerModel: settings.providerModel,
        providerApiKey: _settingsViewModel.providerApiKey,
      ),
    );
    return _dictationSessionViewModel.state != DictationLifecycleState.failed;
  }

  void _settingsChanged() {
    unawaited(_configureShortcutIfNeeded());
    unawaited(_prepareAudioIfNeeded());
    _syncOverlay();
  }

  Future<void> _configureShortcutIfNeeded() async {
    final value = _settingsViewModel.settings.shortcutKey.name;
    if (_configuredShortcut == value) return;
    if (await widget.desktopShortcutGateway.configureShortcut(value)) {
      _configuredShortcut = value;
    }
  }

  Future<void> _prepareAudioIfNeeded() async {
    final value = _settingsViewModel.settings.microphoneId;
    if (_preparedMicrophone == value) return;
    try {
      await widget.dictationEngineGateway.prepareAudio(value);
      _preparedMicrophone = value;
    } catch (_) {
      // Permission denial and disconnected devices are surfaced when the user
      // starts dictation; startup must remain usable so Settings can fix it.
    }
  }

  void _syncOverlay() {
    final overlayState = switch (_dictationSessionViewModel.state) {
      DictationLifecycleState.preparing => DesktopOverlayState.preparing,
      DictationLifecycleState.recording => DesktopOverlayState.recording,
      DictationLifecycleState.finalising ||
      DictationLifecycleState.transcribing ||
      DictationLifecycleState.cleaning ||
      DictationLifecycleState.enhancing ||
      DictationLifecycleState.inserting ||
      DictationLifecycleState.copiedFallback ||
      DictationLifecycleState.completed => DesktopOverlayState.finalising,
      DictationLifecycleState.idle ||
      DictationLifecycleState.cancelled ||
      DictationLifecycleState.failed =>
        _settingsViewModel.settings.showSwarBar
            ? DesktopOverlayState.idle
            : null,
    };
    if (overlayState == null) {
      unawaited(widget.desktopShortcutGateway.hideOverlay());
      return;
    }
    unawaited(
      widget.desktopShortcutGateway.updateOverlay(
        state: overlayState,
        audioLevel: _dictationSessionViewModel.audioLevel,
        isLatched: _activationController.isLatched,
        shortcutKey: _settingsViewModel.settings.shortcutKey.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'swar',
      // Swar is a light-only product (spec §2). No dark theme is registered, so
      // the app never follows the system into dark mode.
      theme: SwarTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: _router,
      builder: (context, child) => RepaintBoundary(
        key: const Key('swar-app-capture-boundary'),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
