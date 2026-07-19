use std::{fs, path::PathBuf};

use directories::ProjectDirs;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct NativeSettings {
    pub language: String,
    pub writing_mode: String,
    pub launch_at_login: bool,
    pub show_in_dock: bool,
    pub keep_models_warm: bool,
    pub show_swar_bar: bool,
    pub dictation_sounds: bool,
    pub mute_music: bool,
    pub suggestions: bool,
    pub announcements: bool,
    pub milestones: bool,
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
}

impl Default for NativeSettings {
    fn default() -> Self {
        Self {
            language: "automatic".to_owned(),
            writing_mode: "clean".to_owned(),
            launch_at_login: false,
            show_in_dock: true,
            keep_models_warm: true,
            show_swar_bar: true,
            dictation_sounds: true,
            mute_music: false,
            suggestions: true,
            announcements: true,
            milestones: true,
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
    }
}
