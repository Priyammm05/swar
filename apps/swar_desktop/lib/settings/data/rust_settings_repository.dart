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
    final modelPath = value.modelPath.isNotEmpty
        ? value.modelPath
        : installedModel.installed
        ? installedModel.path
        : '';
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
      modelPath: modelPath,
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
        modelPath: settings.modelPath,
      ),
    );
  }
}
