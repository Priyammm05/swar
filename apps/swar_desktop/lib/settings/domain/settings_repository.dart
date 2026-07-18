// apps/swar_desktop/lib/settings/domain/settings_repository.dart

import 'package:swar_desktop/settings/domain/swar_settings.dart';

/// Repository Contract. Domain Layer.
/// Rust-backed persistence replaces the Phase 1 in-memory implementation later.
abstract interface class SettingsRepository {
  SwarSettings read();

  void save(SwarSettings settings);
}
