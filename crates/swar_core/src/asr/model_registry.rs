use std::{
    path::Path,
    sync::{
        mpsc::{self, Receiver, Sender},
        LazyLock,
    },
    thread,
};

use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

static MODEL_REGISTRY: LazyLock<ModelRegistry> = LazyLock::new(ModelRegistry::spawn);

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
        result
            .recv()
            .map_err(|_| "the ASR worker stopped while loading the model".to_owned())?
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
        result
            .recv()
            .map_err(|_| "the ASR worker stopped during transcription".to_owned())?
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
        result
            .recv()
            .map_err(|_| "the ASR worker stopped during preview".to_owned())?
    }

    fn unload(&self) -> Result<(), String> {
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Unload { response })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        result
            .recv()
            .map_err(|_| "the ASR worker stopped while unloading the model".to_owned())
    }
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
    let mut loaded: Option<LoadedModel> = None;
    while let Ok(command) = receiver.recv() {
        match command {
            ModelCommand::Prepare {
                model_path,
                response,
            } => {
                let result = ensure_loaded(&mut loaded, &model_path)
                    .map(|already_loaded| ModelStatus { already_loaded });
                let _ = response.send(result);
            }
            ModelCommand::Transcribe {
                model_path,
                language,
                samples,
                preview,
                response,
            } => {
                let result = ensure_loaded(&mut loaded, &model_path).and_then(|_| {
                    let model = loaded
                        .as_ref()
                        .ok_or_else(|| "the offline model did not remain loaded".to_owned())?;
                    transcribe_with_context(
                        &model.context,
                        Path::new(&model.path),
                        &language,
                        &samples,
                        preview,
                    )
                });
                let _ = response.send(result);
            }
            ModelCommand::Unload { response } => {
                loaded = None;
                let _ = response.send(());
            }
        }
    }
}

fn ensure_loaded(loaded: &mut Option<LoadedModel>, model_path: &str) -> Result<bool, String> {
    if loaded
        .as_ref()
        .is_some_and(|model| model.path == model_path)
    {
        return Ok(true);
    }
    let context = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
        .map_err(|error| format!("could not load offline model: {error}"))?;
    *loaded = Some(LoadedModel {
        path: model_path.to_owned(),
        context,
    });
    Ok(false)
}

fn transcribe_with_context(
    context: &WhisperContext,
    model_path: &Path,
    language: &str,
    samples: &[f32],
    preview: bool,
) -> Result<String, String> {
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
    if let Some(vad_model) = vad_model_next_to(model_path) {
        params.set_vad_model_path(vad_model.to_str());
        params.enable_vad(true);
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
            whisper_language: None,
            initial_prompt: Some(
                "Write Hindi and English exactly as spoken using Roman script. Kal meeting hai. Deployment ready hai kya?",
            ),
            detect_language: true,
        },
        _ => LanguageDecoding {
            whisper_language: None,
            // A vocabulary prompt can bias Whisper's language detector toward
            // English. Auto mode intentionally detects from speech alone.
            initial_prompt: None,
            detect_language: true,
        },
    }
}

fn vad_model_next_to(model_path: &Path) -> Option<std::path::PathBuf> {
    let candidate = model_path.parent()?.join("ggml-silero-v6.2.0.bin");
    candidate.is_file().then_some(candidate)
}

fn model_path_for_language(model_path: &Path, language: &str) -> std::path::PathBuf {
    if language.trim().eq_ignore_ascii_case("hindi") {
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
    if model_path.trim().is_empty() || !Path::new(model_path).is_file() {
        Err("model_not_installed: choose an offline Whisper model in Settings".to_owned())
    } else {
        Ok(())
    }
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
    fn language_modes_preserve_the_requested_script_contract() {
        assert_eq!(language_decoding("english").whisper_language, Some("en"));
        assert_eq!(language_decoding("hindi").whisper_language, Some("hi"));

        let hinglish = language_decoding("hinglish");
        assert_eq!(hinglish.whisper_language, None);
        assert!(hinglish
            .initial_prompt
            .is_some_and(|prompt| prompt.contains("Roman script")));
        assert_eq!(language_decoding("automatic").whisper_language, None);
    }
}
