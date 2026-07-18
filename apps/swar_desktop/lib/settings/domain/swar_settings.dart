// apps/swar_desktop/lib/settings/domain/swar_settings.dart

enum SwarLanguagePreference { automatic, english, hindi, hinglish }

enum SwarWritingMode { raw, clean, intent }

/// Domain Model.
/// Settings that the Phase 1 shell can edit without owning product logic.
final class SwarSettings {
  const SwarSettings({
    this.language = SwarLanguagePreference.automatic,
    this.writingMode = SwarWritingMode.clean,
    this.launchAtLogin = false,
    this.showInDock = true,
    this.keepModelsWarm = true,
  });

  final SwarLanguagePreference language;
  final SwarWritingMode writingMode;
  final bool launchAtLogin;
  final bool showInDock;
  final bool keepModelsWarm;

  SwarSettings copyWith({
    SwarLanguagePreference? language,
    SwarWritingMode? writingMode,
    bool? launchAtLogin,
    bool? showInDock,
    bool? keepModelsWarm,
  }) {
    return SwarSettings(
      language: language ?? this.language,
      writingMode: writingMode ?? this.writingMode,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      showInDock: showInDock ?? this.showInDock,
      keepModelsWarm: keepModelsWarm ?? this.keepModelsWarm,
    );
  }
}
