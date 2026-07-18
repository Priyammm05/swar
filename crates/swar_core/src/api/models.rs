use std::{
    fs::{self, File},
    io::{Read, Write},
    path::PathBuf,
};

use directories::ProjectDirs;
use flutter_rust_bridge::frb;
use sha1::{Digest, Sha1};

const RECOMMENDED_MODEL_FILE: &str = "ggml-base.bin";
const RECOMMENDED_MODEL_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin";
const RECOMMENDED_MODEL_SHA1: &str = "465707469ff3a37a2b9b8d8f89f2f99de7299dac";
const MINIMUM_MODEL_BYTES: u64 = 100_000_000;

#[derive(Clone, Debug)]
pub struct OfflineModelStatus {
    pub path: String,
    pub installed: bool,
    pub size_bytes: u64,
    pub model_id: String,
}

/// Returns the supported multilingual starter model without accessing the network.
#[frb(sync)]
pub fn recommended_model_status() -> Result<OfflineModelStatus, String> {
    let path = recommended_model_path()?;
    Ok(status_for(path))
}

/// Downloads the official whisper.cpp multilingual base model to app support.
/// The partial file is verified before it atomically replaces any existing model.
pub fn install_recommended_model() -> Result<OfflineModelStatus, String> {
    let destination = recommended_model_path()?;
    if status_for(destination.clone()).installed {
        return Ok(status_for(destination));
    }

    let parent = destination
        .parent()
        .ok_or_else(|| "model directory is unavailable".to_owned())?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let partial = destination.with_extension("bin.partial");
    let response = ureq::get(RECOMMENDED_MODEL_URL)
        .call()
        .map_err(|error| format!("model download failed: {error}"))?;
    let mut reader = response.into_reader();
    let mut file = File::create(&partial).map_err(|error| error.to_string())?;
    let mut hasher = Sha1::new();
    let mut buffer = [0_u8; 64 * 1024];
    let mut size_bytes = 0_u64;

    loop {
        let count = reader.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 {
            break;
        }
        file.write_all(&buffer[..count])
            .map_err(|error| error.to_string())?;
        hasher.update(&buffer[..count]);
        size_bytes += count as u64;
    }
    file.sync_all().map_err(|error| error.to_string())?;

    let digest = format!("{:x}", hasher.finalize());
    if size_bytes < MINIMUM_MODEL_BYTES || digest != RECOMMENDED_MODEL_SHA1 {
        let _ = fs::remove_file(&partial);
        return Err("downloaded model failed integrity verification".to_owned());
    }

    fs::rename(&partial, &destination).map_err(|error| error.to_string())?;
    Ok(status_for(destination))
}

fn recommended_model_path() -> Result<PathBuf, String> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")
        .ok_or_else(|| "application support directory is unavailable".to_owned())?;
    Ok(directories
        .data_local_dir()
        .join("models")
        .join(RECOMMENDED_MODEL_FILE))
}

fn status_for(path: PathBuf) -> OfflineModelStatus {
    let metadata = fs::metadata(&path).ok();
    let size_bytes = metadata.as_ref().map_or(0, fs::Metadata::len);
    OfflineModelStatus {
        path: path.to_string_lossy().into_owned(),
        installed: metadata.is_some_and(|value| value.is_file())
            && size_bytes >= MINIMUM_MODEL_BYTES,
        size_bytes,
        model_id: "whisper-base-multilingual".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recommended_model_is_multilingual() {
        assert_eq!(RECOMMENDED_MODEL_FILE, "ggml-base.bin");
        assert!(!RECOMMENDED_MODEL_FILE.contains(".en."));
    }
}
