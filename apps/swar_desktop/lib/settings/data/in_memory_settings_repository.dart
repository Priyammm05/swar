// apps/swar_desktop/lib/settings/data/in_memory_settings_repository.dart

import 'package:swar_desktop/settings/domain/settings_repository.dart';
import 'package:swar_desktop/settings/domain/swar_settings.dart';

/// Fake Repository. Data Layer.
final class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository({SwarSettings initial = const SwarSettings()})
    : _settings = initial;

  SwarSettings _settings;

  @override
  SwarSettings read() => _settings;

  @override
  void save(SwarSettings settings) {
    _settings = settings;
  }
}
