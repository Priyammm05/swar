use std::{
    panic::{self, AssertUnwindSafe},
    path::Path,
    sync::{
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
        LazyLock,
    },
    thread,
    time::Duration,
};

use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

static MODEL_REGISTRY: LazyLock<ModelRegistry> = LazyLock::new(ModelRegistry::spawn);

// Watchdog ceilings for the single ASR worker. They are deliberately generous —
// real decodes finish far sooner — and exist only so a wedged whisper.cpp call
// can never hang the caller (and, through it, the reserved coordinator) forever.
const MODEL_LOAD_TIMEOUT: Duration = Duration::from_secs(120);
const FINAL_DECODE_TIMEOUT: Duration = Duration::from_secs(300);
const PREVIEW_DECODE_TIMEOUT: Duration = Duration::from_secs(60);
const UNLOAD_TIMEOUT: Duration = Duration::from_secs(30);

// Upper bound handed to whisper.cpp (10 minutes at 16 kHz). Capture already
// clamps dictation length; this is a defensive ceiling against a degenerate
// buffer reaching native decoding.
const MAX_DECODE_SAMPLES: usize = 16_000 * 600;

enum ModelCommand {
    Prepare {
        model_path: String,
        response: Sender<Result<ModelStatus, String>>,
    },
    Transcribe {
        model_path: String,
        language: String,
        samples: Vec<f32>,
        preview: bool,
        response: Sender<Result<String, String>>,
    },
    Unload {
        response: Sender<()>,
    },
}

#[derive(Clone, Debug)]
pub(crate) struct ModelStatus {
    pub already_loaded: bool,
}

struct LoadedModel {
    path: String,
    context: WhisperContext,
}

/// Number of warm Whisper contexts kept resident. 2 lets a common language pair
/// (e.g. English/Auto + Hindi) both stay warm so alternating dictations do not
/// reload a ~190 MB model on every switch (CPU/thermal spike).
const MAX_WARM_CONTEXTS: usize = 2;

/// A tiny most-recently-used cache of warm Whisper contexts owned by the single
/// ASR worker thread.
struct ModelCache {
    entries: Vec<LoadedModel>,
}

impl ModelCache {
    fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    /// Ensures the model at `model_path` is warm. Returns `true` if it was
    /// already resident (no reload), `false` if it was just loaded.
    fn ensure(&mut self, model_path: &str) -> Result<bool, String> {
        if let Some(index) = self
            .entries
            .iter()
            .position(|model| model.path == model_path)
        {
            let entry = self.entries.remove(index);
            self.entries.insert(0, entry);
            return Ok(true);
        }
        let context =
            WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
                .map_err(|error| format!("could not load offline model: {error}"))?;
        self.entries.insert(
            0,
            LoadedModel {
                path: model_path.to_owned(),
                context,
            },
        );
        self.entries.truncate(MAX_WARM_CONTEXTS);
        Ok(false)
    }

    fn get(&self, model_path: &str) -> Option<&LoadedModel> {
        self.entries.iter().find(|model| model.path == model_path)
    }

    fn clear(&mut self) {
        self.entries.clear();
    }
}

struct ModelRegistry {
    commands: Sender<ModelCommand>,
}

impl ModelRegistry {
    fn spawn() -> Self {
        let (commands, receiver) = mpsc::channel();
        thread::Builder::new()
            .name("swar-asr-worker".to_owned())
            .spawn(move || run_worker(receiver))
            .expect("the dedicated ASR worker must start");
        Self { commands }
    }

    fn prepare(&self, model_path: &str) -> Result<ModelStatus, String> {
        ensure_model_file(model_path)?;
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Prepare {
                model_path: model_path.to_owned(),
                response,
            })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, MODEL_LOAD_TIMEOUT, "loading the model")?
    }

    fn transcribe(
        &self,
        model_path: &str,
        language: &str,
        samples: &[f32],
    ) -> Result<String, String> {
        ensure_model_file(model_path)?;
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Transcribe {
                model_path: model_path.to_owned(),
                language: language.to_owned(),
                samples: samples.to_vec(),
                preview: false,
                response,
            })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, FINAL_DECODE_TIMEOUT, "transcribing")?
    }

    fn transcribe_preview(
        &self,
        model_path: &str,
        language: &str,
        samples: &[f32],
    ) -> Result<String, String> {
        ensure_model_file(model_path)?;
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Transcribe {
                model_path: model_path.to_owned(),
                language: language.to_owned(),
                samples: samples.to_vec(),
                preview: true,
                response,
            })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, PREVIEW_DECODE_TIMEOUT, "generating a preview")?
    }

    fn unload(&self) -> Result<(), String> {
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Unload { response })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, UNLOAD_TIMEOUT, "unloading the model")
    }
}

/// Waits for the ASR worker's reply with a watchdog. A timeout or a dropped
/// sender both surface as a recoverable error instead of blocking indefinitely.
fn await_worker_response<T>(
    result: &Receiver<T>,
    timeout: Duration,
    action: &'static str,
) -> Result<T, String> {
    result.recv_timeout(timeout).map_err(|error| match error {
        RecvTimeoutError::Timeout => format!("the ASR worker timed out while {action}"),
        RecvTimeoutError::Disconnected => format!("the ASR worker stopped while {action}"),
    })
}

pub(crate) fn prepare(model_path: &str) -> Result<ModelStatus, String> {
    MODEL_REGISTRY.prepare(model_path)
}

pub(crate) fn prepare_for_language(
    model_path: &str,
    language: &str,
) -> Result<ModelStatus, String> {
    let selected = model_path_for_language(Path::new(model_path), language);
    MODEL_REGISTRY.prepare(&selected.to_string_lossy())
}

pub(crate) fn transcribe(
    model_path: &str,
    language: &str,
    samples: &[f32],
) -> Result<String, String> {
    let selected = model_path_for_language(Path::new(model_path), language);
    MODEL_REGISTRY.transcribe(&selected.to_string_lossy(), language, samples)
}

pub(crate) fn transcribe_preview(
    model_path: &str,
    language: &str,
    samples: &[f32],
) -> Result<String, String> {
    let selected = model_path_for_language(Path::new(model_path), language);
    MODEL_REGISTRY.transcribe_preview(&selected.to_string_lossy(), language, samples)
}

pub(crate) fn unload() -> Result<(), String> {
    MODEL_REGISTRY.unload()
}

fn run_worker(receiver: Receiver<ModelCommand>) {
    // whisper.cpp's default stderr callback prints decoded token text. Redirect
    // it into whisper-rs' disabled-by-default hooks so release logs can never
    // contain a user's dictation.
    whisper_rs::install_logging_hooks();
    let mut cache = ModelCache::new();
    while let Ok(command) = receiver.recv() {
        match command {
            ModelCommand::Prepare {
                model_path,
                response,
            } => {
                let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
                    cache
                        .ensure(&model_path)
                        .map(|already_loaded| ModelStatus { already_loaded })
                }));
                let result = outcome.unwrap_or_else(|_| {
                    cache.clear();
                    Err("the offline model failed while loading".to_owned())
                });
                let _ = response.send(result);
            }
            ModelCommand::Transcribe {
                model_path,
                language,
                samples,
                preview,
                response,
            } => {
                // A panic inside whisper.cpp would otherwise unwind through the
                // C frame (undefined behaviour) and kill this single worker,
                // permanently disabling all future dictation. Catch it, drop the
                // possibly-corrupt contexts, and reply with a recoverable error.
                let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
                    cache.ensure(&model_path).and_then(|_| {
                        let model = cache
                            .get(&model_path)
                            .ok_or_else(|| "the offline model did not remain loaded".to_owned())?;
                        transcribe_with_context(
                            &model.context,
                            Path::new(&model.path),
                            &language,
                            &samples,
                            preview,
                        )
                    })
                }));
                let result = outcome.unwrap_or_else(|_| {
                    cache.clear();
                    Err("the offline model failed during transcription".to_owned())
                });
                let _ = response.send(result);
            }
            ModelCommand::Unload { response } => {
                cache.clear();
                let _ = response.send(());
            }
        }
    }
}

fn transcribe_with_context(
    context: &WhisperContext,
    model_path: &Path,
    language: &str,
    samples: &[f32],
    preview: bool,
) -> Result<String, String> {
    // Degenerate input (empty, over-long, or NaN/Inf from an upstream resample)
    // can make whisper.cpp abort or return nothing useful. An empty transcript
    // is the correct, safe result for a buffer with no decodable audio.
    let Some(samples) = prepared_decode_input(samples) else {
        return Ok(String::new());
    };
    let samples = samples.as_ref();
    let mut state = context.create_state().map_err(|error| error.to_string())?;
    let mut params = if preview {
        FullParams::new(SamplingStrategy::Greedy { best_of: 1 })
    } else {
        FullParams::new(SamplingStrategy::BeamSearch {
            beam_size: 5,
            patience: -1.0,
        })
    };
    params.set_translate(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_no_timestamps(true);
    params.set_single_segment(true);
    params.set_n_threads(available_threads());
    params.set_suppress_blank(true);
    params.set_no_speech_thold(0.60);
    params.set_temperature(0.0);
    params.set_temperature_inc(if preview { 0.0 } else { 0.2 });
    let decoding = language_decoding(language);
    params.set_language(decoding.whisper_language);
    params.set_detect_language(decoding.detect_language);
    if let Some(prompt) = decoding.initial_prompt {
        params.set_initial_prompt(prompt);
    }
    // Final dictation has already passed Swar's conservative native energy
    // gate and has been trimmed with edge padding. Running Silero again here
    // can discard valid sub-two-second utterances and return no segments.
    // Preview snapshots have not passed that final gate, so they retain VAD.
    if uses_whisper_vad(preview) {
        if let Some(vad_model) = vad_model_next_to(model_path) {
            params.set_vad_model_path(vad_model.to_str());
            params.enable_vad(true);
        }
    }
    state
        .full(params, samples)
        .map_err(|error| error.to_string())?;
    Ok(state
        .as_iter()
        .map(|segment| segment.to_string())
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_owned())
}

fn uses_whisper_vad(preview: bool) -> bool {
    preview
}

/// Returns decode-ready samples, or `None` when the buffer is empty. NaN/Inf are
/// neutralised and the length is capped so nothing degenerate reaches the FFI.
fn prepared_decode_input(samples: &[f32]) -> Option<std::borrow::Cow<'_, [f32]>> {
    use std::borrow::Cow;
    if samples.is_empty() {
        return None;
    }
    let too_long = samples.len() > MAX_DECODE_SAMPLES;
    let has_non_finite = samples.iter().any(|sample| !sample.is_finite());
    if !too_long && !has_non_finite {
        return Some(Cow::Borrowed(samples));
    }
    let cleaned = samples
        .iter()
        .take(MAX_DECODE_SAMPLES)
        .map(|sample| if sample.is_finite() { *sample } else { 0.0 })
        .collect::<Vec<f32>>();
    Some(Cow::Owned(cleaned))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LanguageDecoding {
    whisper_language: Option<&'static str>,
    initial_prompt: Option<&'static str>,
    detect_language: bool,
}

/// Whisper's Hindi token requests Devanagari. Hinglish must remain in Roman
/// script, so it intentionally uses multilingual detection plus a Roman-script
/// context prompt instead of being forced through the Hindi decoder.
fn language_decoding(language: &str) -> LanguageDecoding {
    match language.trim().to_ascii_lowercase().as_str() {
        "english" => LanguageDecoding {
            whisper_language: Some("en"),
            initial_prompt: None,
            detect_language: false,
        },
        "hindi" => LanguageDecoding {
            whisper_language: Some("hi"),
            initial_prompt: None,
            detect_language: false,
        },
        "hinglish" => LanguageDecoding {
            // Decode as Hindi, never free auto-detect: a null language lets
            // whisper.cpp misidentify short or accented Hindi as Urdu/Arabic and
            // emit a completely different script. Hindi decoding is reliable for
            // Hindi and code-switched English; the Devanagari it returns is then
            // transliterated to Roman by the language stage after transcription.
            whisper_language: Some("hi"),
            initial_prompt: None,
            detect_language: false,
        },
        // Auto: also decode as Hindi rather than free auto-detect, so spoken
        // Hindi is recognised reliably (and later romanised) instead of being
        // misdetected. Pure-English users should pick the English mode.
        _ => LanguageDecoding {
            whisper_language: Some("hi"),
            initial_prompt: None,
            detect_language: false,
        },
    }
}

fn vad_model_next_to(model_path: &Path) -> Option<std::path::PathBuf> {
    let candidate = model_path.parent()?.join("ggml-silero-v6.2.0.bin");
    candidate.is_file().then_some(candidate)
}

fn model_path_for_language(model_path: &Path, language: &str) -> std::path::PathBuf {
    // The Indic-tuned model recognises Hindi (and code-switched English) best, so
    // the Hindi-centric modes use it. Auto stays on the general multilingual model
    // for a better balance when the speaker switches to full English.
    let lower = language.trim().to_ascii_lowercase();
    if lower == "hindi" || lower == "hinglish" {
        if let Some(parent) = model_path.parent() {
            let hindi = parent.join("ggml-hi-small.bin");
            if hindi.is_file() {
                return hindi;
            }
        }
    }
    model_path.to_owned()
}

fn ensure_model_file(model_path: &str) -> Result<(), String> {
    let path = Path::new(model_path);
    if model_path.trim().is_empty() || !path.is_file() {
        return Err("model_not_installed: choose an offline Whisper model in Settings".to_owned());
    }
    // Cheap size re-check before the file reaches whisper.cpp. A model that
    // passed SHA-256 at install but was later truncated (disk-full, interrupted
    // OS update) would otherwise be handed to native decoding and could abort.
    let length = std::fs::metadata(path)
        .map(|metadata| metadata.len())
        .unwrap_or(0);
    if length < crate::api::models::expected_minimum_bytes(model_path) {
        return Err(
            "model_incomplete: the offline model file is incomplete; reinstall it in Settings"
                .to_owned(),
        );
    }
    Ok(())
}

fn available_threads() -> i32 {
    thread::available_parallelism()
        .map(|count| count.get().saturating_sub(1).clamp(1, 8) as i32)
        .unwrap_or(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_model_is_rejected_before_the_worker_is_contacted() {
        let error = ensure_model_file("/definitely/not/a/swar/model.bin")
            .expect_err("missing model should fail");
        assert!(error.starts_with("model_not_installed:"));
    }

    #[test]
    fn asr_thread_count_leaves_capacity_for_the_desktop() {
        assert!((1..=8).contains(&available_threads()));
    }

    #[test]
    fn language_modes_force_a_concrete_decode_never_free_auto_detect() {
        // English decodes as English; every Hindi-capable mode decodes as Hindi
        // rather than null auto-detect (which misidentifies short/accented Hindi
        // as Urdu/Arabic). Roman output is produced by the later transliteration
        // stage, not by the decoder, so no mode leaves the language null.
        assert_eq!(language_decoding("english").whisper_language, Some("en"));
        assert_eq!(language_decoding("hindi").whisper_language, Some("hi"));
        assert_eq!(language_decoding("hinglish").whisper_language, Some("hi"));
        assert_eq!(language_decoding("automatic").whisper_language, Some("hi"));

        for mode in ["english", "hindi", "hinglish", "automatic"] {
            let decoding = language_decoding(mode);
            assert!(
                !decoding.detect_language,
                "{mode} must not use detection-only mode"
            );
            assert!(
                decoding.initial_prompt.is_none(),
                "{mode} must not bias the decoder with a prompt"
            );
        }
    }

    #[test]
    fn final_dictation_does_not_apply_a_second_vad_pass() {
        assert!(!uses_whisper_vad(false));
        assert!(uses_whisper_vad(true));
    }

    #[test]
    fn worker_response_times_out_instead_of_blocking_forever() {
        // The sender stays alive but never replies, so only the watchdog can
        // unblock the caller.
        let (_sender, receiver) = mpsc::channel::<Result<String, String>>();
        let error = await_worker_response(&receiver, Duration::from_millis(10), "transcribing")
            .expect_err("a silent worker must time out");
        assert!(error.contains("timed out"), "unexpected error: {error}");
    }

    #[test]
    fn worker_response_reports_a_stopped_worker() {
        let (sender, receiver) = mpsc::channel::<Result<String, String>>();
        drop(sender);
        let error = await_worker_response(&receiver, Duration::from_secs(1), "transcribing")
            .expect_err("a dropped sender must surface a stopped worker");
        assert!(error.contains("stopped"), "unexpected error: {error}");
    }

    #[test]
    fn decode_input_rejects_empty_and_sanitises_non_finite_samples() {
        assert!(prepared_decode_input(&[]).is_none());

        // A clean buffer is borrowed, not copied.
        let clean = [0.1_f32, -0.2, 0.3];
        assert!(matches!(
            prepared_decode_input(&clean),
            Some(std::borrow::Cow::Borrowed(_))
        ));

        // NaN/Inf are replaced with silence so nothing degenerate reaches the FFI.
        let dirty = [0.1_f32, f32::NAN, f32::INFINITY, -0.3];
        let prepared = prepared_decode_input(&dirty).expect("non-empty input");
        assert!(prepared.iter().all(|sample| sample.is_finite()));
        assert_eq!(prepared.len(), dirty.len());
    }
}
