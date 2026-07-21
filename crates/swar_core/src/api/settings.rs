use std::{fs, path::PathBuf};

use directories::ProjectDirs;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// What Swar persists between launches.
///
/// Every field here must be read by something that changes behaviour. Eight
/// were removed once nothing read them: `language`, `launch_at_login`,
/// `show_in_dock`, `dictation_sounds`, `mute_music`, `suggestions`,
/// `announcements`, and `milestones`. They survived the removal of their
/// Settings rows and went on being written to disk, which left a settings file
/// stating things about the product that were not true. `launch_at_login` in
/// particular persisted as `true` on machines where no launch agent has ever
/// existed.
///
/// `#[serde(default)]` plus serde's habit of ignoring unknown keys means an
/// existing settings.json holding those keys still loads; they are simply
/// dropped the next time it is written. No migration is needed.
///
/// When one of those features is built, its field comes back in the same
/// commit as its implementation, so it is true from the first line.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct NativeSettings {
    pub writing_mode: String,
    pub keep_models_warm: bool,
    pub show_swar_bar: bool,
    pub paste_automatically: bool,
    pub restore_clipboard: bool,
    pub learn_from_edits: bool,
    pub model_path: String,
    pub microphone_id: String,
    pub shortcut_key: String,
    pub excluded_applications: Vec<String>,
    pub enhancement_provider: String,
    pub provider_endpoint: String,
    pub provider_model: String,
    /// How many days of local dictation history to keep before it is pruned.
    /// One of 30/90/180/365; other values fall back to the default.
    pub history_retention_days: u32,
}

/// Retention choices offered in Settings. History and learning data stay on this
/// machine, so the user controls how long it is kept.
pub(crate) const RETENTION_DAY_CHOICES: [u32; 4] = [30, 90, 180, 365];

fn normalize_retention_days(value: u32) -> u32 {
    if RETENTION_DAY_CHOICES.contains(&value) {
        value
    } else {
        crate::storage::DEFAULT_HISTORY_RETENTION_DAYS
    }
}

/// The configured retention window, loaded from disk and validated, used by the
/// storage layer to prune old history. Falls back to the default when settings
/// are missing or hold an unexpected value.
pub(crate) fn configured_history_retention_days() -> u32 {
    load_settings()
        .map(|settings| normalize_retention_days(settings.history_retention_days))
        .unwrap_or(crate::storage::DEFAULT_HISTORY_RETENTION_DAYS)
}

impl Default for NativeSettings {
    fn default() -> Self {
        Self {
            writing_mode: "clean".to_owned(),
            keep_models_warm: true,
            show_swar_bar: true,
            paste_automatically: true,
            restore_clipboard: true,
            learn_from_edits: false,
            model_path: String::new(),
            microphone_id: String::new(),
            shortcut_key: "option".to_owned(),
            excluded_applications: Vec::new(),
            enhancement_provider: "local".to_owned(),
            provider_endpoint: String::new(),
            provider_model: String::new(),
            history_retention_days: crate::storage::DEFAULT_HISTORY_RETENTION_DAYS,
        }
    }
}

#[frb(sync)]
pub fn load_settings() -> Result<NativeSettings, String> {
    let path = settings_path()?;
    if !path.is_file() {
        return Ok(NativeSettings::default());
    }
    let bytes = fs::read(path).map_err(|error| error.to_string())?;
    serde_json::from_slice(&bytes).map_err(|error| error.to_string())
}

#[frb(sync)]
pub fn save_settings(settings: NativeSettings) -> Result<(), String> {
    let path = settings_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| "settings directory is unavailable".to_owned())?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let temporary = path.with_extension("json.tmp");
    let bytes = serde_json::to_vec_pretty(&settings).map_err(|error| error.to_string())?;
    fs::write(&temporary, bytes).map_err(|error| error.to_string())?;
    fs::rename(temporary, path).map_err(|error| error.to_string())
}

fn settings_path() -> Result<PathBuf, String> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")
        .ok_or_else(|| "application support directory is unavailable".to_owned())?;
    Ok(directories.data_local_dir().join("settings.json"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_keep_transcription_local_and_usable() {
        let settings = NativeSettings::default();
        assert!(settings.paste_automatically);
        assert!(settings.restore_clipboard);
        assert_eq!(settings.writing_mode, "clean");
        assert_eq!(settings.enhancement_provider, "local");
        assert_eq!(
            settings.history_retention_days,
            crate::storage::DEFAULT_HISTORY_RETENTION_DAYS
        );
    }

    #[test]
    fn retention_days_falls_back_when_out_of_range() {
        for valid in RETENTION_DAY_CHOICES {
            assert_eq!(normalize_retention_days(valid), valid);
        }
        assert_eq!(
            normalize_retention_days(7),
            crate::storage::DEFAULT_HISTORY_RETENTION_DAYS
        );
        assert_eq!(
            normalize_retention_days(0),
            crate::storage::DEFAULT_HISTORY_RETENTION_DAYS
        );
    }
}
