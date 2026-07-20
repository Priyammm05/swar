use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    time::Duration,
};

use directories::ProjectDirs;
use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};

// A model download idles (no bytes) for at most this long before it is treated
// as stalled, so a half-open connection cannot hang the installer forever.
const DOWNLOAD_CONNECT_TIMEOUT: Duration = Duration::from_secs(30);
const DOWNLOAD_IDLE_TIMEOUT: Duration = Duration::from_secs(60);

const RECOMMENDED_MODEL_FILE: &str = "ggml-small-q5_1.bin";
const RECOMMENDED_MODEL_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin";
const RECOMMENDED_MODEL_SHA256: &str =
    "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb";
const MINIMUM_MODEL_BYTES: u64 = 180_000_000;
const VAD_MODEL_FILE: &str = "ggml-silero-v6.2.0.bin";
const VAD_MODEL_URL: &str =
    "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin";
const VAD_MODEL_SHA256: &str = "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987";
const VAD_MODEL_BYTES: u64 = 885_098;
const HINDI_MODEL_FILE: &str = "ggml-hi-small.bin";
const HINDI_MODEL_URL: &str =
    "https://huggingface.co/ukta-app/indic-whisper-ggml/resolve/main/ggml-hi-small.bin";
const HINDI_MODEL_SHA256: &str = "6813fed7ffa6c3fa14490c1f1788d2d8b6e3b7badf59a2f75fb4c5c21cf00f3f";
const HINDI_MODEL_BYTES: u64 = 190_085_487;
// The Hinglish-tuned pack (Oriserve Hindi2Hinglish "Apex", ggml q5_0). It emits
// romanised Latin directly, so Hinglish/Auto recover code-switched English at the
// source ("complete", not "kanplit"). Larger and slower than the small model —
// selected only for the Hinglish/Auto routes.
const HINGLISH_MODEL_FILE: &str = "ggml-apex-hinglish-q5_0.bin";
const HINGLISH_MODEL_URL: &str =
    "https://huggingface.co/Marquestra/Whisper-Hindi2Hinglish-Apex-GGML/resolve/main/ggml-apex-hinglish-q5_0.bin";
const HINGLISH_MODEL_SHA256: &str =
    "9d877151b15cec1feb9110cfbc0a3162cf377bcc0ab1935174226f461cf60f13";
const HINGLISH_MODEL_BYTES: u64 = 574_041_195;
// The fast Hinglish pack (Swift, whisper-base). Locally converted for now, so it
// is only size-guarded (no pinned download yet).
const SWIFT_HINGLISH_MODEL_FILE: &str = "ggml-swift-hinglish.bin";
const SWIFT_HINGLISH_MODEL_BYTES: u64 = 147_951_465;

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
    let parent = destination
        .parent()
        .ok_or_else(|| "model directory is unavailable".to_owned())?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    if !verified_file(&destination, MINIMUM_MODEL_BYTES, RECOMMENDED_MODEL_SHA256) {
        download_verified(
            RECOMMENDED_MODEL_URL,
            &destination,
            MINIMUM_MODEL_BYTES,
            RECOMMENDED_MODEL_SHA256,
        )?;
    }
    let vad_destination = parent.join(VAD_MODEL_FILE);
    if !verified_file(&vad_destination, VAD_MODEL_BYTES, VAD_MODEL_SHA256) {
        download_verified(
            VAD_MODEL_URL,
            &vad_destination,
            VAD_MODEL_BYTES,
            VAD_MODEL_SHA256,
        )?;
    }
    let hindi_destination = parent.join(HINDI_MODEL_FILE);
    if !verified_file(&hindi_destination, HINDI_MODEL_BYTES, HINDI_MODEL_SHA256) {
        download_verified(
            HINDI_MODEL_URL,
            &hindi_destination,
            HINDI_MODEL_BYTES,
            HINDI_MODEL_SHA256,
        )?;
    }
    let hinglish_destination = parent.join(HINGLISH_MODEL_FILE);
    if !verified_file(
        &hinglish_destination,
        HINGLISH_MODEL_BYTES,
        HINGLISH_MODEL_SHA256,
    ) {
        download_verified(
            HINGLISH_MODEL_URL,
            &hinglish_destination,
            HINGLISH_MODEL_BYTES,
            HINGLISH_MODEL_SHA256,
        )?;
    }
    Ok(status_for(destination))
}

fn download_verified(
    url: &str,
    destination: &Path,
    minimum_bytes: u64,
    expected_sha256: &str,
) -> Result<(), String> {
    let partial = destination.with_extension("bin.partial");
    // Guarantee the partial is removed on every failure path (network error,
    // disk-full mid-write, or a verification mismatch), not only on mismatch.
    let outcome = download_to_partial(url, &partial, minimum_bytes, expected_sha256);
    if outcome.is_err() {
        let _ = fs::remove_file(&partial);
    }
    outcome?;
    fs::rename(&partial, destination).map_err(|error| error.to_string())
}

fn download_to_partial(
    url: &str,
    partial: &Path,
    minimum_bytes: u64,
    expected_sha256: &str,
) -> Result<(), String> {
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(DOWNLOAD_CONNECT_TIMEOUT)
        .timeout_read(DOWNLOAD_IDLE_TIMEOUT)
        .build();
    let response = agent
        .get(url)
        .call()
        .map_err(|error| format!("model download failed: {error}"))?;
    let mut reader = response.into_reader();
    let mut file = File::create(partial).map_err(|error| error.to_string())?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    let mut size_bytes = 0_u64;
    loop {
        let count = reader
            .read(&mut buffer)
            .map_err(|error| error.to_string())?;
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
    if size_bytes < minimum_bytes || digest != expected_sha256 {
        return Err("downloaded model failed integrity verification".to_owned());
    }
    Ok(())
}

/// The expected minimum on-disk size for a known model file, used as a cheap
/// integrity guard before the file is handed to whisper.cpp.
pub(crate) fn expected_minimum_bytes(model_path: &str) -> u64 {
    match Path::new(model_path)
        .file_name()
        .and_then(|name| name.to_str())
    {
        Some(HINDI_MODEL_FILE) => HINDI_MODEL_BYTES,
        Some(HINGLISH_MODEL_FILE) => HINGLISH_MODEL_BYTES,
        Some(SWIFT_HINGLISH_MODEL_FILE) => SWIFT_HINGLISH_MODEL_BYTES,
        Some(VAD_MODEL_FILE) => VAD_MODEL_BYTES,
        _ => MINIMUM_MODEL_BYTES,
    }
}

fn file_present_with_min_size(path: &Path, minimum_bytes: u64) -> bool {
    fs::metadata(path).is_ok_and(|metadata| metadata.is_file() && metadata.len() >= minimum_bytes)
}

fn verified_file(path: &std::path::Path, minimum_bytes: u64, expected_sha256: &str) -> bool {
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let Ok(metadata) = file.metadata() else {
        return false;
    };
    if !metadata.is_file() || metadata.len() < minimum_bytes {
        return false;
    }
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let Ok(count) = file.read(&mut buffer) else {
            return false;
        };
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    format!("{:x}", hasher.finalize()) == expected_sha256
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
        // This runs on the Dart UI isolate (#[frb(sync)]). Use a cheap
        // presence + size check, not a full SHA-256 of ~190 MB models, which
        // would freeze the UI on every Settings render. The strong hash
        // guarantee still holds at install time and at model load.
        installed: metadata.is_some_and(|value| value.is_file())
            && size_bytes >= MINIMUM_MODEL_BYTES
            && path.parent().is_some_and(|parent| {
                file_present_with_min_size(&parent.join(VAD_MODEL_FILE), VAD_MODEL_BYTES)
                    && file_present_with_min_size(&parent.join(HINDI_MODEL_FILE), HINDI_MODEL_BYTES)
            }),
        size_bytes,
        model_id: "whisper-small-q5_1-multilingual".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recommended_model_is_multilingual() {
        assert_eq!(RECOMMENDED_MODEL_FILE, "ggml-small-q5_1.bin");
        assert!(!RECOMMENDED_MODEL_FILE.contains(".en."));
        assert_eq!(VAD_MODEL_FILE, "ggml-silero-v6.2.0.bin");
        assert_eq!(HINDI_MODEL_FILE, "ggml-hi-small.bin");
    }

    #[test]
    fn expected_minimum_bytes_matches_each_known_model() {
        assert_eq!(
            expected_minimum_bytes("/models/ggml-hi-small.bin"),
            HINDI_MODEL_BYTES
        );
        assert_eq!(
            expected_minimum_bytes("/models/ggml-silero-v6.2.0.bin"),
            VAD_MODEL_BYTES
        );
        assert_eq!(
            expected_minimum_bytes("/models/ggml-small-q5_1.bin"),
            MINIMUM_MODEL_BYTES
        );
    }
}
