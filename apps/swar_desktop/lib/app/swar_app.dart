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
import 'package:swar_desktop/settings/domain/swar_settings.dart';
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

  /// Whether the field focused when this dictation started was a password, OTP,
  /// or payment field. Captured at start (the focus can move afterwards) so the
  /// overlay can show the private-field state for the whole session.
  bool _sessionFieldIsSecure = false;

  /// Whether the last insertion-permission request was granted. Drives the
  /// permission state on the overlay.
  bool _insertionPermissionGranted = true;

  /// When the current recording began, for the overlay's elapsed timer.
  DateTime? _recordingStartedAt;

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
    // The microphone is opened only while dictating (lazily, on the first
    // capture) and released when it ends, so it is never held open at rest and
    // the OS recording indicator stays off until you actually dictate.
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
    // Privacy P0: check the focused field before any audio is retained. A secure
    // (password) field means the dictation still inserts but is never persisted.
    final isSensitive = await widget.desktopShortcutGateway
        .focusedFieldIsSecure();
    _sessionFieldIsSecure = isSensitive;
    _recordingStartedAt = DateTime.now();
    // Read the field's existing text once, before recording, so the local model
    // can match its register. Native returns nothing for a secure field, and an
    // excluded application gets no context either — the same rule that already
    // withholds its name.
    final cursorText = (isSensitive || excluded)
        ? const FocusedFieldText()
        : await widget.desktopShortcutGateway.focusedFieldText();
    if (settings.pasteAutomatically) {
      _insertionPermissionGranted = await widget.desktopShortcutGateway
          .requestInsertionPermission();
    }
    await _dictationSessionViewModel.start(
      DictationEngineConfig(
        modelPath: settings.modelPath,
        microphoneId: settings.microphoneId,
        // Swar recognises English only.
        language: 'english',
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
        isSensitive: isSensitive,
        cursorTextBefore: cursorText.before,
        cursorTextAfter: cursorText.after,
      ),
    );
    return _dictationSessionViewModel.state != DictationLifecycleState.failed;
  }

  void _settingsChanged() {
    unawaited(_configureShortcutIfNeeded());
    _syncOverlay();
  }

  Future<void> _configureShortcutIfNeeded() async {
    final value = _settingsViewModel.settings.shortcutKey.name;
    if (_configuredShortcut == value) return;
    if (await widget.desktopShortcutGateway.configureShortcut(value)) {
      _configuredShortcut = value;
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
      _recordingStartedAt = null;
      unawaited(widget.desktopShortcutGateway.hideOverlay());
      return;
    }
    final settings = _settingsViewModel.settings;
    unawaited(
      widget.desktopShortcutGateway.updateOverlay(
        DesktopOverlaySnapshot(
          state: overlayState,
          audioLevel: _dictationSessionViewModel.audioLevel,
          isLatched: _activationController.isLatched,
          shortcutKey: settings.shortcutKey.name,
          condition: _overlayCondition(),
          // The engine only ever reports a not-yet-final tail while recording,
          // so there is no confirmed segment to draw in white until the final
          // text is inserted.
          transcriptPartial: _dictationSessionViewModel.partialText ?? '',
          // Swar recognises English only, so the chip is fixed.
          language: 'EN',
          elapsedMs: _recordingElapsed().inMilliseconds,
          writingMode: switch (settings.writingMode) {
            SwarWritingMode.raw => SwarOverlayWritingMode.raw,
            SwarWritingMode.clean => SwarOverlayWritingMode.clean,
            SwarWritingMode.intent => SwarOverlayWritingMode.intent,
          },
        ),
      ),
    );
  }

  /// The exceptional state the overlay should show, most urgent first, or `null`
  /// for the ordinary recording and processing flow.
  ///
  /// `noField` is deliberately absent: nothing in the current pipeline reports
  /// "invoked with no text field focused" distinctly from a failed insertion,
  /// which already surfaces as `copied`. Wiring it needs a native focused-role
  /// check, so the state is drawn but never triggered yet.
  DesktopOverlayCondition? _overlayCondition() {
    if (!_dictationSessionViewModel.recommendedModelStatus.installed) {
      return DesktopOverlayCondition.model;
    }
    if (!_insertionPermissionGranted) {
      return DesktopOverlayCondition.permission;
    }
    return switch (_dictationSessionViewModel.state) {
      DictationLifecycleState.copiedFallback => DesktopOverlayCondition.copied,
      DictationLifecycleState.completed => DesktopOverlayCondition.inserted,
      _ when _sessionFieldIsSecure => DesktopOverlayCondition.secure,
      _ => null,
    };
  }

  /// The language chip names the mode the user chose, never a guess. Automatic
  /// reads `AUTO` rather than `HI+EN`: the language is not decided until the
  /// engine detects it mid-transcription, so claiming Hindi while someone speaks
  /// English would be wrong. Surfacing the detected language needs the engine to
  /// report it back, which it does not do yet.

  Duration _recordingElapsed() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
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
      // Scroll without a visible scrollbar track (design feedback).
      scrollBehavior: const _SwarScrollBehavior(),
      routerConfig: _router,
      builder: (context, child) => RepaintBoundary(
        key: const Key('swar-app-capture-boundary'),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// App-wide scroll behavior that hides the scrollbar track. Swar's pages still
/// scroll (wheel, trackpad, drag); only the visible scrollbar is suppressed.
class _SwarScrollBehavior extends MaterialScrollBehavior {
  const _SwarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
