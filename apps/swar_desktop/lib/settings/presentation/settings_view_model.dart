// apps/swar_desktop/lib/settings/presentation/settings_view_model.dart

import 'package:flutter/foundation.dart';
import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

/// View Model. Presentation Layer.
/// Holds only the settings snapshot required by the visible controls.
final class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required SettingsRepository repository})
    : _repository = repository,
      _settings = repository.read();

  final SettingsRepository _repository;
  SwarSettings _settings;
  String _providerApiKey = '';

  SwarSettings get settings => _settings;
  String get providerApiKey => _providerApiKey;

  void setLanguage(SwarLanguagePreference language) {
    _save(_settings.copyWith(language: language));
  }

  void setWritingMode(SwarWritingMode writingMode) {
    _save(_settings.copyWith(writingMode: writingMode));
  }

  void setLaunchAtLogin({required bool enabled}) {
    _save(_settings.copyWith(launchAtLogin: enabled));
  }

  void setShowInDock({required bool enabled}) {
    _save(_settings.copyWith(showInDock: enabled));
  }

  void setKeepModelsWarm({required bool enabled}) {
    _save(_settings.copyWith(keepModelsWarm: enabled));
  }

  void setShowSwarBar({required bool enabled}) =>
      _save(_settings.copyWith(showSwarBar: enabled));

  void setDictationSounds({required bool enabled}) =>
      _save(_settings.copyWith(dictationSounds: enabled));

  void setMuteMusic({required bool enabled}) =>
      _save(_settings.copyWith(muteMusic: enabled));

  void setSuggestions({required bool enabled}) =>
      _save(_settings.copyWith(suggestions: enabled));

  void setAnnouncements({required bool enabled}) =>
      _save(_settings.copyWith(announcements: enabled));

  void setMilestones({required bool enabled}) =>
      _save(_settings.copyWith(milestones: enabled));

  void setPasteAutomatically({required bool enabled}) =>
      _save(_settings.copyWith(pasteAutomatically: enabled));

  void setRestoreClipboard({required bool enabled}) =>
      _save(_settings.copyWith(restoreClipboard: enabled));

  void setLearnFromEdits({required bool enabled}) =>
      _save(_settings.copyWith(learnFromEdits: enabled));

  void setModelPath(String value) =>
      _save(_settings.copyWith(modelPath: value.trim()));

  void setMicrophoneId(String value) =>
      _save(_settings.copyWith(microphoneId: value.trim()));

  void setShortcutKey(SwarShortcutKey value) =>
      _save(_settings.copyWith(shortcutKey: value));

  void setExcludedApplications(List<String> values) => _save(
    _settings.copyWith(
      excludedApplications: values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false),
    ),
  );

  void setEnhancementProvider(SwarEnhancementProvider value) =>
      _save(_settings.copyWith(enhancementProvider: value));

  void setProviderEndpoint(String value) =>
      _save(_settings.copyWith(providerEndpoint: value.trim()));

  void setProviderModel(String value) =>
      _save(_settings.copyWith(providerModel: value.trim()));

  /// Secrets deliberately live only for the current app process.
  void setProviderApiKey(String value) {
    _providerApiKey = value.trim();
    notifyListeners();
  }

  void _save(SwarSettings settings) {
    _settings = settings;
    _repository.save(settings);
    notifyListeners();
  }
}
