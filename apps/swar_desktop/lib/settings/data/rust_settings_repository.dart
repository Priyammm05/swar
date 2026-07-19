import 'package:swar_desktop/generated_bridge/api/settings.dart' as native;
import 'package:swar_desktop/generated_bridge/api/models.dart' as models;
import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

/// Persists user preferences in the native app-support directory.
final class RustSettingsRepository implements SettingsRepository {
  @override
  SwarSettings read() {
    final value = native.loadSettings();
    final installedModel = models.recommendedModelStatus();
    final normalizedModelPath = value.modelPath.replaceAll('\\', '/');
    final usesLegacyManagedModel = normalizedModelPath.endsWith(
      '/models/ggml-base.bin',
    );
    final modelPath =
        installedModel.installed &&
            (value.modelPath.isEmpty || usesLegacyManagedModel)
        ? installedModel.path
        : value.modelPath;
    return SwarSettings(
      language: SwarLanguagePreference.values.byName(value.language),
      writingMode: SwarWritingMode.values.byName(value.writingMode),
      launchAtLogin: value.launchAtLogin,
      showInDock: value.showInDock,
      keepModelsWarm: value.keepModelsWarm,
      showSwarBar: value.showSwarBar,
      dictationSounds: value.dictationSounds,
      muteMusic: value.muteMusic,
      suggestions: value.suggestions,
      announcements: value.announcements,
      milestones: value.milestones,
      pasteAutomatically: value.pasteAutomatically,
      restoreClipboard: value.restoreClipboard,
      learnFromEdits: value.learnFromEdits,
      modelPath: modelPath,
      microphoneId: value.microphoneId,
      shortcutKey:
          SwarShortcutKey.values
              .where((key) => key.name == value.shortcutKey)
              .firstOrNull ??
          SwarShortcutKey.option,
      excludedApplications: List.unmodifiable(value.excludedApplications),
      enhancementProvider:
          SwarEnhancementProvider.values
              .where((provider) => provider.name == value.enhancementProvider)
              .firstOrNull ??
          SwarEnhancementProvider.local,
      providerEndpoint: value.providerEndpoint,
      providerModel: value.providerModel,
    );
  }

  @override
  void save(SwarSettings settings) {
    native.saveSettings(
      settings: native.NativeSettings(
        language: settings.language.name,
        writingMode: settings.writingMode.name,
        launchAtLogin: settings.launchAtLogin,
        showInDock: settings.showInDock,
        keepModelsWarm: settings.keepModelsWarm,
        showSwarBar: settings.showSwarBar,
        dictationSounds: settings.dictationSounds,
        muteMusic: settings.muteMusic,
        suggestions: settings.suggestions,
        announcements: settings.announcements,
        milestones: settings.milestones,
        pasteAutomatically: settings.pasteAutomatically,
        restoreClipboard: settings.restoreClipboard,
        learnFromEdits: settings.learnFromEdits,
        modelPath: settings.modelPath,
        microphoneId: settings.microphoneId,
        shortcutKey: settings.shortcutKey.name,
        excludedApplications: settings.excludedApplications,
        enhancementProvider: settings.enhancementProvider.name,
        providerEndpoint: settings.providerEndpoint,
        providerModel: settings.providerModel,
      ),
    );
  }
}
