// apps/swar_desktop/lib/settings/domain/swar_settings.dart

enum SwarLanguagePreference { automatic, english, hindi, hinglish }

enum SwarWritingMode { raw, clean, intent }

enum SwarShortcutKey { option, control }

enum SwarEnhancementProvider { local, byok }

/// Domain Model.
/// Settings that the Phase 1 shell can edit without owning product logic.
final class SwarSettings {
  const SwarSettings({
    this.language = SwarLanguagePreference.automatic,
    this.writingMode = SwarWritingMode.clean,
    this.launchAtLogin = false,
    this.showInDock = true,
    this.keepModelsWarm = true,
    this.showSwarBar = true,
    this.dictationSounds = true,
    this.muteMusic = false,
    this.suggestions = true,
    this.announcements = true,
    this.milestones = true,
    this.pasteAutomatically = true,
    this.restoreClipboard = true,
    this.learnFromEdits = false,
    this.modelPath = '',
    this.microphoneId = '',
    this.shortcutKey = SwarShortcutKey.option,
    this.excludedApplications = const [],
    this.enhancementProvider = SwarEnhancementProvider.local,
    this.providerEndpoint = '',
    this.providerModel = '',
    this.historyRetentionDays = 365,
  });

  final SwarLanguagePreference language;
  final SwarWritingMode writingMode;
  final bool launchAtLogin;
  final bool showInDock;
  final bool keepModelsWarm;
  final bool showSwarBar;
  final bool dictationSounds;
  final bool muteMusic;
  final bool suggestions;
  final bool announcements;
  final bool milestones;
  final bool pasteAutomatically;
  final bool restoreClipboard;
  final bool learnFromEdits;
  final String modelPath;
  final String microphoneId;
  final SwarShortcutKey shortcutKey;
  final List<String> excludedApplications;
  final SwarEnhancementProvider enhancementProvider;
  final String providerEndpoint;
  final String providerModel;
  final int historyRetentionDays;

  SwarSettings copyWith({
    SwarLanguagePreference? language,
    SwarWritingMode? writingMode,
    bool? launchAtLogin,
    bool? showInDock,
    bool? keepModelsWarm,
    bool? showSwarBar,
    bool? dictationSounds,
    bool? muteMusic,
    bool? suggestions,
    bool? announcements,
    bool? milestones,
    bool? pasteAutomatically,
    bool? restoreClipboard,
    bool? learnFromEdits,
    String? modelPath,
    String? microphoneId,
    SwarShortcutKey? shortcutKey,
    List<String>? excludedApplications,
    SwarEnhancementProvider? enhancementProvider,
    String? providerEndpoint,
    String? providerModel,
    int? historyRetentionDays,
  }) {
    return SwarSettings(
      language: language ?? this.language,
      writingMode: writingMode ?? this.writingMode,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      showInDock: showInDock ?? this.showInDock,
      keepModelsWarm: keepModelsWarm ?? this.keepModelsWarm,
      showSwarBar: showSwarBar ?? this.showSwarBar,
      dictationSounds: dictationSounds ?? this.dictationSounds,
      muteMusic: muteMusic ?? this.muteMusic,
      suggestions: suggestions ?? this.suggestions,
      announcements: announcements ?? this.announcements,
      milestones: milestones ?? this.milestones,
      pasteAutomatically: pasteAutomatically ?? this.pasteAutomatically,
      restoreClipboard: restoreClipboard ?? this.restoreClipboard,
      learnFromEdits: learnFromEdits ?? this.learnFromEdits,
      modelPath: modelPath ?? this.modelPath,
      microphoneId: microphoneId ?? this.microphoneId,
      shortcutKey: shortcutKey ?? this.shortcutKey,
      excludedApplications: excludedApplications ?? this.excludedApplications,
      enhancementProvider: enhancementProvider ?? this.enhancementProvider,
      providerEndpoint: providerEndpoint ?? this.providerEndpoint,
      providerModel: providerModel ?? this.providerModel,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
    );
  }
}
