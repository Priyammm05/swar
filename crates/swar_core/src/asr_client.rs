//! Client for the fast ASR helper (`swar_asr_server`).
//!
//! Mirrors `llm_client`: a dedicated worker owns the child process, serialises
//! requests, applies a watchdog timeout, and restarts a crashed helper. This
//! module has NO ONNX dependency — the helper is a separate binary, so the two
//! ONNX runtimes never link into the app framework. The captured 16 kHz mono
//! audio is written to a temp WAV and its path is handed to the helper.

use std::{
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
        LazyLock,
    },
    thread,
    time::Duration,
};

use directories::ProjectDirs;

const RESPONSE_SENTINEL: &str = "@@SWARASR@@ ";
/// Floor for one transcription: covers a cold model load (~3 s) plus decoding,
/// and warm short clips return well under a second.
const MINIMUM_TRANSCRIBE_TIMEOUT: Duration = Duration::from_secs(30);

/// Share of real time allowed for a decode before the helper is given up on.
///
/// A flat 30 s ceiling silently failed long dictation. Capture allows 300 s, and
/// the 1000-case corpus showed decodes climbing to 29.7 s against that ceiling
/// with nothing left: every case past roughly 265 s of audio timed out and fell
/// back to whisper, which is both slower and less accurate. Measured real-time
/// factor is 0.086 to 0.119, so half of real time leaves a wide margin while
/// still bounding a genuinely wedged helper.
const TRANSCRIBE_TIMEOUT_SHARE: f64 = 0.5;

/// How long to allow for `samples` at 16 kHz.
fn transcribe_timeout(samples: usize) -> Duration {
    let seconds = samples as f64 / 16_000.0;
    Duration::from_secs_f64(seconds * TRANSCRIBE_TIMEOUT_SHARE).max(MINIMUM_TRANSCRIBE_TIMEOUT)
}

static ASR: LazyLock<AsrClient> = LazyLock::new(AsrClient::spawn);

struct Job {
    wav: String,
    language: String,
    /// Scaled to the clip's length by `transcribe_timeout`.
    timeout: Duration,
    response: Sender<Result<String, String>>,
}

struct AsrClient {
    jobs: Sender<Job>,
}

impl AsrClient {
    fn spawn() -> Self {
        let (jobs, receiver) = mpsc::channel();
        thread::Builder::new()
            .name("swar-asr-client".to_owned())
            .spawn(move || run_worker(receiver))
            .expect("the ASR client worker must start");
        Self { jobs }
    }
}

/// Transcribes 16 kHz mono `samples` in `language` via the fast helper. Returns
/// an error when the helper or models are unavailable so the caller can fall back
/// to whisper.
pub(crate) fn transcribe(samples: &[f32], language: &str) -> Result<String, String> {
    if helper_path().is_none() || model_dirs().is_none() {
        return Err("fast ASR is not installed".to_owned());
    }
    let wav = write_temp_wav(samples)?;
    let timeout = transcribe_timeout(samples.len());
    let (response, result) = mpsc::channel();
    ASR.jobs
        .send(Job {
            wav: wav.to_string_lossy().into_owned(),
            language: language.to_owned(),
            timeout,
            response,
        })
        .map_err(|_| "the ASR worker is unavailable".to_owned())?;
    let outcome = result
        // The worker is bounded by the same deadline, so allow it a moment to
        // report its own timeout before this side gives up and hides the reason.
        .recv_timeout(timeout + Duration::from_secs(5))
        .map_err(|error| match error {
            RecvTimeoutError::Timeout => "the ASR helper timed out".to_owned(),
            RecvTimeoutError::Disconnected => "the ASR helper stopped".to_owned(),
        })?;
    let _ = std::fs::remove_file(&wav);
    outcome
}

/// Warms the fast engines so the first real dictation does not pay their cold
/// load (~2-3 s for Parakeet's 622 MB encoder). Sends a short silent request for
/// each available engine — English loads Parakeet, Hindi loads IndicConformer
/// when its pack is installed. Best-effort; the transcript is discarded. Callers
/// run this off the UI thread.
pub(crate) fn warm() {
    if helper_path().is_none() || model_dirs().is_none() {
        return;
    }
    let silence = vec![0f32; 16_000 / 5]; // 200 ms is enough to force a model load.
    let _ = transcribe(&silence, "english");
    if crate::api::models::indic_models_installed() {
        let _ = transcribe(&silence, "hindi");
    }
}

fn run_worker(receiver: Receiver<Job>) {
    let mut helper: Option<Helper> = None;
    while let Ok(job) = receiver.recv() {
        // Resolve the model dirs per job (a couple of cheap `is_file` checks) so a
        // pack installed from Settings mid-session is picked up on the next
        // dictation without restarting the helper.
        let (parakeet_dir, indic_dir) = model_dirs().unwrap_or_default();
        if helper.is_none() {
            helper = match spawn_helper() {
                Ok(h) => Some(h),
                Err(e) => {
                    let _ = job.response.send(Err(e));
                    continue;
                }
            };
        }
        let request = serde_json::json!({
            "wav": job.wav,
            "language": job.language,
            "parakeet_dir": parakeet_dir,
            "indic_dir": indic_dir,
        })
        .to_string();
        let result = exchange(
            helper.as_mut().expect("just spawned"),
            &request,
            job.timeout,
        );
        if result.is_err() {
            helper = None; // Restart a crashed/wedged helper next time.
        }
        let _ = job.response.send(result);
    }
}

struct Helper {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<Option<String>>,
}

impl Drop for Helper {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn exchange(helper: &mut Helper, request: &str, timeout: Duration) -> Result<String, String> {
    helper
        .stdin
        .write_all(format!("{request}\n").as_bytes())
        .and_then(|_| helper.stdin.flush())
        .map_err(|_| "could not send to the ASR helper".to_owned())?;
    loop {
        match helper.lines.recv_timeout(timeout) {
            Ok(Some(line)) => {
                let Some(payload) = line.strip_prefix(RESPONSE_SENTINEL) else {
                    continue;
                };
                let value: serde_json::Value =
                    serde_json::from_str(payload).map_err(|_| "invalid ASR JSON".to_owned())?;
                if value["ok"].as_bool() != Some(true) {
                    return Err(value["error"]
                        .as_str()
                        .unwrap_or("ASR helper failed")
                        .to_owned());
                }
                return Ok(value["text"].as_str().unwrap_or("").to_owned());
            }
            Ok(None) | Err(RecvTimeoutError::Disconnected) => {
                return Err("the ASR helper exited".to_owned())
            }
            Err(RecvTimeoutError::Timeout) => return Err("the ASR helper timed out".to_owned()),
        }
    }
}

fn spawn_helper() -> Result<Helper, String> {
    let path = helper_path().ok_or_else(|| "the ASR helper is not installed".to_owned())?;
    // The bundled onnxruntime/sherpa dylibs sit beside the helper; make sure the
    // loader finds them without relying on install-time rpath edits.
    let mut command = Command::new(&path);
    if let Some(dir) = path.parent() {
        let existing = std::env::var("DYLD_LIBRARY_PATH").unwrap_or_default();
        let combined = if existing.is_empty() {
            dir.to_string_lossy().into_owned()
        } else {
            format!("{}:{existing}", dir.to_string_lossy())
        };
        command.env("DYLD_LIBRARY_PATH", combined);
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("could not start the ASR helper: {error}"))?;
    let stdin = child.stdin.take().ok_or_else(|| "asr stdin".to_owned())?;
    let stdout = child.stdout.take().ok_or_else(|| "asr stdout".to_owned())?;
    let (tx, lines) = mpsc::channel();
    thread::Builder::new()
        .name("swar-asr-reader".to_owned())
        .spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(l) => {
                        if tx.send(Some(l)).is_err() {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }
            let _ = tx.send(None);
        })
        .map_err(|e| e.to_string())?;
    Ok(Helper {
        child,
        stdin,
        lines,
    })
}

/// Locates the helper binary: env override, then beside the app executable, then
/// the cargo target layout.
fn helper_path() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("SWAR_ASR_SERVER") {
        let p = PathBuf::from(p);
        if p.exists() {
            return Some(p);
        }
    }
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    [
        dir.join("swar_asr_server"),
        dir.join("../Resources/swar_asr_server"),
    ]
    .into_iter()
    .find(|candidate| candidate.exists())
}

/// The Parakeet and IndicConformer model directories, or `None` if either is
/// missing. Env overrides support development against out-of-tree models.
fn model_dirs() -> Option<(String, String)> {
    let (parakeet, indic) = match (
        std::env::var("SWAR_PARAKEET_DIR").ok(),
        std::env::var("SWAR_INDIC_DIR").ok(),
    ) {
        (Some(p), Some(i)) => (PathBuf::from(p), PathBuf::from(i)),
        _ => {
            let models = ProjectDirs::from("dev", "Swar", "Swar")?
                .data_local_dir()
                .join("models");
            (models.join("parakeet-v3"), models.join("indic-conformer"))
        }
    };
    let parakeet_ok = parakeet.join("encoder.int8.onnx").is_file();
    let indic_ok = indic.join("onnx/encoder_quantized_int8.onnx").is_file();
    if parakeet_ok && indic_ok {
        Some((
            parakeet.to_string_lossy().into_owned(),
            indic.to_string_lossy().into_owned(),
        ))
    } else {
        None
    }
}

/// Writes mono f32 samples to a 16-bit PCM WAV at 16 kHz in the temp dir.
fn write_temp_wav(samples: &[f32]) -> Result<PathBuf, String> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir();
    let id = COUNTER.fetch_add(1, Ordering::Relaxed);
    let path = dir.join(format!("swar-asr-{}-{}.wav", std::process::id(), id));
    let n = samples.len();
    let byte_rate = 16000u32 * 2;
    let data_len = (n * 2) as u32;
    let mut buf = Vec::with_capacity(44 + n * 2);
    buf.extend_from_slice(b"RIFF");
    buf.extend_from_slice(&(36 + data_len).to_le_bytes());
    buf.extend_from_slice(b"WAVEfmt ");
    buf.extend_from_slice(&16u32.to_le_bytes());
    buf.extend_from_slice(&1u16.to_le_bytes()); // PCM
    buf.extend_from_slice(&1u16.to_le_bytes()); // mono
    buf.extend_from_slice(&16000u32.to_le_bytes());
    buf.extend_from_slice(&byte_rate.to_le_bytes());
    buf.extend_from_slice(&2u16.to_le_bytes()); // block align
    buf.extend_from_slice(&16u16.to_le_bytes()); // bits
    buf.extend_from_slice(b"data");
    buf.extend_from_slice(&data_len.to_le_bytes());
    for &s in samples {
        let v = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
        buf.extend_from_slice(&v.to_le_bytes());
    }
    std::fs::write(&path, &buf).map_err(|e| format!("write temp wav: {e}"))?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_clips_keep_the_cold_load_floor() {
        // Half of a two second clip is a second, which would not cover the ~3 s
        // model load on the first call.
        assert_eq!(
            transcribe_timeout(16_000 * 2),
            MINIMUM_TRANSCRIBE_TIMEOUT,
            "short clips must not fall below the cold-load floor"
        );
    }

    #[test]
    fn the_longest_capture_gets_far_more_time_than_it_needs() {
        // Capture allows 300 s. The 1000-case corpus measured a real-time factor
        // of 0.086 to 0.119, so that clip decodes in roughly 26 to 36 s.
        let longest = transcribe_timeout(16_000 * 300);
        assert!(
            longest >= Duration::from_secs(120),
            "300 s of audio got only {longest:?}"
        );
    }

    #[test]
    fn the_length_that_used_to_time_out_now_fits() {
        // The corpus cliff: every case past roughly 265 s of audio hit the old
        // flat 30 s ceiling and fell back to whisper. The slowest decode that did
        // succeed took 29.7 s of the 30 available.
        let previously_failing = transcribe_timeout(16_000 * 265);
        assert!(
            previously_failing > Duration::from_secs(30),
            "265 s of audio still capped at {previously_failing:?}"
        );
    }

    #[test]
    fn the_deadline_rises_with_the_clip() {
        assert!(transcribe_timeout(16_000 * 300) > transcribe_timeout(16_000 * 120));
    }
}
