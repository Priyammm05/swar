// apps/swar_desktop/lib/settings/domain/settings_repository.dart

import 'package:swar_desktop/settings/domain/swar_settings.dart';

/// Repository Contract. Domain Layer.
/// Rust-backed persistence replaces the Phase 1 in-memory implementation later.
abstract interface class SettingsRepository {
  SwarSettings read();

  void save(SwarSettings settings);

  /// Fetches the optional on-device cleanup model, about 2 GB.
  ///
  /// Only ever called because somebody chose it in Settings. It used to run
  /// unasked on first launch, which is how a first run came to be 2.8 GB when
  /// recognition itself needs 819 MB. Completes when the download does; callers
  /// are not expected to wait, since cleanup falls back to the deterministic
  /// editor until the weights arrive.
  Future<void> installCleanupModel();
}
