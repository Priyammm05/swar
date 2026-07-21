// apps/swar_desktop/lib/settings/domain/swar_settings.dart

enum SwarWritingMode { raw, clean, intent }

enum SwarShortcutKey { option, control }

/// How Swar tidies a transcript after recognition.
///
/// [local] is the deterministic editor: instant, predictable, and the default.
/// [embedded] adds an on-device 3B model, which is a 2 GB download and is opted
/// into rather than assumed. [byok] sends text to an OpenAI-compatible endpoint
/// the user configures.
enum SwarEnhancementProvider { local, embedded, byok }

/// Domain Model.
/// Settings that the Phase 1 shell can edit without owning product logic.
final class SwarSettings {
  const SwarSettings({
    this.writingMode = SwarWritingMode.clean,
    this.keepModelsWarm = true,
    this.showSwarBar = true,
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

  final SwarWritingMode writingMode;
  final bool keepModelsWarm;
  final bool showSwarBar;
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
    SwarWritingMode? writingMode,
    bool? keepModelsWarm,
    bool? showSwarBar,
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
      writingMode: writingMode ?? this.writingMode,
      keepModelsWarm: keepModelsWarm ?? this.keepModelsWarm,
      showSwarBar: showSwarBar ?? this.showSwarBar,
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
