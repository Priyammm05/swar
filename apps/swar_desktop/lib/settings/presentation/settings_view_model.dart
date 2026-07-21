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

  void setWritingMode(SwarWritingMode writingMode) {
    _save(_settings.copyWith(writingMode: writingMode));
  }

  void setKeepModelsWarm({required bool enabled}) {
    _save(_settings.copyWith(keepModelsWarm: enabled));
  }

  void setShowSwarBar({required bool enabled}) =>
      _save(_settings.copyWith(showSwarBar: enabled));

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

  /// History and learning data stay on this machine; the user controls how long
  /// Swar keeps it (30/90/180/365 days).
  void setHistoryRetentionDays(int value) =>
      _save(_settings.copyWith(historyRetentionDays: value));

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
