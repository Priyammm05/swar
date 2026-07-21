use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
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
// The on-device cleanup LLM (Qwen2.5-3B-Instruct, GGUF q4_k_m, Apache-2.0). Used
// by the embedded-llm enhancer to do Wispr-style context cleanup — fixing
// homophones ("Mike" -> "mic"), punctuation, and capitalisation that a pure
// speech model cannot resolve from sound alone. Large (~2 GB) and adds latency,
// so it is optional: present only if the user installs it.
const EMBEDDED_LLM_MODEL_FILE: &str = "qwen2.5-3b-instruct-q4_k_m.gguf";
const EMBEDDED_LLM_MODEL_URL: &str =
    "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf";
const EMBEDDED_LLM_MODEL_SHA256: &str =
    "626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d";
const EMBEDDED_LLM_MODEL_BYTES: u64 = 2_104_932_768;

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
        Some(EMBEDDED_LLM_MODEL_FILE) => EMBEDDED_LLM_MODEL_BYTES,
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

/// The on-disk path to the embedded cleanup LLM, or `None` when it is not
/// installed. Presence + minimum-size only (no full hash) so it is cheap on the
/// hot dictation path; the strong SHA-256 guarantee still holds at install time.
pub(crate) fn embedded_llm_model_path() -> Option<PathBuf> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")?;
    let path = directories
        .data_local_dir()
        .join("models")
        .join(EMBEDDED_LLM_MODEL_FILE);
    file_present_with_min_size(&path, EMBEDDED_LLM_MODEL_BYTES).then_some(path)
}

/// Downloads the embedded cleanup LLM (~2 GB) into the models directory,
/// verifying its SHA-256 before it atomically replaces any existing file.
pub fn install_embedded_llm_model() -> Result<OfflineModelStatus, String> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")
        .ok_or_else(|| "application support directory is unavailable".to_owned())?;
    let models_dir = directories.data_local_dir().join("models");
    fs::create_dir_all(&models_dir).map_err(|error| error.to_string())?;
    let destination = models_dir.join(EMBEDDED_LLM_MODEL_FILE);
    if !verified_file(
        &destination,
        EMBEDDED_LLM_MODEL_BYTES,
        EMBEDDED_LLM_MODEL_SHA256,
    ) {
        download_verified(
            EMBEDDED_LLM_MODEL_URL,
            &destination,
            EMBEDDED_LLM_MODEL_BYTES,
            EMBEDDED_LLM_MODEL_SHA256,
        )?;
    }
    Ok(status_for(destination))
}

/// Guards the one-time background download so repeated `prepare` calls in a
/// single process never start overlapping 2 GB downloads.
static LLM_DOWNLOAD_STARTED: AtomicBool = AtomicBool::new(false);

/// Kicks off a one-time background download of the ~2 GB cleanup model when it is
/// absent, so cleanup "just works" without the user opening a setting. It is
/// non-blocking and best-effort: until the model lands, cleanup stays on the
/// instant deterministic editor; on success it warms the helper so the next
/// dictation is fast; on failure it clears the guard so a later launch can retry.
pub(crate) fn ensure_embedded_llm_model_download() {
    if embedded_llm_model_path().is_some() {
        return;
    }
    if LLM_DOWNLOAD_STARTED.swap(true, Ordering::SeqCst) {
        return; // Already downloading (or downloaded) in this process.
    }
    std::thread::spawn(|| match install_embedded_llm_model() {
        Ok(status) => {
            let _ = crate::llm_client::prepare(
                &status.path,
                crate::enhancement::cleanup_system_prompt(),
            );
        }
        Err(_) => {
            LLM_DOWNLOAD_STARTED.store(false, Ordering::SeqCst);
        }
    });
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
            }),
        size_bytes,
        model_id: "whisper-small-q5_1-multilingual".to_owned(),
    }
}

// ===== Fast ASR models (Parakeet + IndicConformer) =====
//
// These are multi-file ONNX bundles served by the fast helper (`swar_asr_server`).
// Unlike the single-file whisper/LLM models, each bundle is a directory of files,
// so the pinned manifest below drives a per-file verified download. Missing models
// simply mean recognition stays on whisper — never a failure.

/// One downloadable file in an ASR bundle. `path` is relative to the bundle's
/// directory under `models/`; `url` is pinned to an immutable repo revision.
#[derive(serde::Deserialize)]
struct AsrFile {
    path: String,
    url: String,
    sha256: String,
    bytes: u64,
}

#[derive(serde::Deserialize)]
struct AsrBundle {
    dir: String,
    files: Vec<AsrFile>,
}

#[derive(serde::Deserialize)]
struct AsrManifest {
    parakeet: AsrBundle,
}

/// The pinned manifest of every fast-ASR file (URL + SHA-256 + size), embedded at
/// compile time. Generated from the validated local models.
const ASR_MANIFEST_JSON: &str = include_str!("../asr_models.json");

fn asr_manifest() -> Result<AsrManifest, String> {
    serde_json::from_str(ASR_MANIFEST_JSON).map_err(|error| error.to_string())
}

fn models_dir() -> Result<PathBuf, String> {
    let directories = ProjectDirs::from("dev", "Swar", "Swar")
        .ok_or_else(|| "application support directory is unavailable".to_owned())?;
    Ok(directories.data_local_dir().join("models"))
}

/// True when every file of `bundle` is present at its expected size. A cheap
/// presence + size check for the hot path and Settings; the strong SHA-256
/// guarantee still holds at install time.
fn bundle_installed(bundle: &AsrBundle) -> bool {
    let Ok(root) = models_dir() else {
        return false;
    };
    let base = root.join(&bundle.dir);
    bundle
        .files
        .iter()
        .all(|file| file_present_with_min_size(&base.join(&file.path), file.bytes))
}

/// Downloads every file of `bundle` that is missing or fails verification into the
/// models directory, each verified by SHA-256 before it atomically replaces any
/// existing file. Callers must run this off the UI thread.
fn install_bundle(bundle: &AsrBundle) -> Result<(), String> {
    let base = models_dir()?.join(&bundle.dir);
    for file in &bundle.files {
        let destination = base.join(&file.path);
        if verified_file(&destination, file.bytes, &file.sha256) {
            continue;
        }
        let parent = destination
            .parent()
            .ok_or_else(|| "asr model directory is unavailable".to_owned())?;
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        download_verified(&file.url, &destination, file.bytes, &file.sha256)?;
    }
    Ok(())
}

/// True when the default English engine (Parakeet) is installed.
pub(crate) fn parakeet_installed() -> bool {
    asr_manifest().is_ok_and(|manifest| bundle_installed(&manifest.parakeet))
}

/// True when the optional Indian-languages pack (IndicConformer) is installed.

/// Downloads the optional Indian-languages pack (~670 MB). Exposed so a Settings
/// action can install it on demand; until then Hindi/Hinglish/Indian speech uses
/// the whisper fallback. Blocking, so Flutter must call it off the UI isolate.

/// The Indian-languages pack install state for Settings (presence + size only,
/// cheap enough for a `#[frb(sync)]` render).
#[frb(sync)]

/// Best-effort recursive byte size of a directory tree; 0 when absent.
fn directory_size(path: &Path) -> u64 {
    let Ok(entries) = fs::read_dir(path) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| match entry.metadata() {
            Ok(metadata) if metadata.is_dir() => directory_size(&entry.path()),
            Ok(metadata) => metadata.len(),
            Err(_) => 0,
        })
        .sum()
}

/// Guards the one-time background download so repeated `prepare` calls never start
/// overlapping Parakeet downloads in a single process.
static PARAKEET_DOWNLOAD_STARTED: AtomicBool = AtomicBool::new(false);

/// Kicks off a one-time background download of the default English engine
/// (Parakeet, ~670 MB) when it is absent, so fast English recognition "just works"
/// without the user opening a setting. The Indian-languages pack is NOT fetched
/// here — it is opt-in via `install_indic_models` from Settings. Non-blocking and
/// best-effort: until Parakeet lands, recognition stays on whisper; on failure it
/// clears the guard so a later launch can retry.
pub(crate) fn ensure_parakeet_download() {
    if parakeet_installed() {
        return;
    }
    if PARAKEET_DOWNLOAD_STARTED.swap(true, Ordering::SeqCst) {
        return; // Already downloading (or downloaded) in this process.
    }
    std::thread::spawn(|| {
        let installed =
            asr_manifest().is_ok_and(|manifest| install_bundle(&manifest.parakeet).is_ok());
        if !installed {
            PARAKEET_DOWNLOAD_STARTED.store(false, Ordering::SeqCst);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recommended_model_is_multilingual() {
        assert_eq!(RECOMMENDED_MODEL_FILE, "ggml-small-q5_1.bin");
        assert!(!RECOMMENDED_MODEL_FILE.contains(".en."));
        assert_eq!(VAD_MODEL_FILE, "ggml-silero-v6.2.0.bin");
    }

    #[test]
    fn asr_manifest_parses_and_pins_every_file() {
        let manifest = asr_manifest().expect("embedded ASR manifest must parse");
        assert_eq!(manifest.parakeet.dir, "parakeet-v3");
        // The helper looks for these exact entrypoints (see asr_client::model_dirs
        // and swar_asr_server), so a manifest that dropped them would silently
        // disable fast ASR.
        assert!(manifest
            .parakeet
            .files
            .iter()
            .any(|f| f.path == "encoder.int8.onnx"));
        for file in &manifest.parakeet.files {
            assert_eq!(file.sha256.len(), 64, "sha256 for {}", file.path);
            assert!(file.bytes > 0, "size for {}", file.path);
            assert!(file.url.starts_with("https://"), "url for {}", file.path);
        }
    }

    #[test]
    fn expected_minimum_bytes_matches_each_known_model() {
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
