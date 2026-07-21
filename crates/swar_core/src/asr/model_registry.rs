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

/// Everything reaching whisper has already been resampled to this rate.
const DECODE_SAMPLE_RATE: u32 = 16_000;

/// Whisper's encoder window: 30 s at 16 kHz. `audio::segment` keeps every decode
/// inside one window; this stays as the guard for anything that slips past it.
const FULL_WINDOW_SAMPLES: usize = DECODE_SAMPLE_RATE as usize * 30;

enum ModelCommand {
    Prepare {
        model_path: String,
        response: Sender<Result<ModelStatus, String>>,
    },
    Transcribe {
        model_path: String,
        language: String,
        samples: Vec<f32>,
        /// User vocabulary fed to whisper.cpp as an initial prompt so proper
        /// nouns are spelled right at the source (swar.md §7). Empty = no bias.
        hotwords: String,
        preview: bool,
        response: Sender<Result<String, String>>,
    },
    DetectLanguage {
        model_path: String,
        samples: Vec<f32>,
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
        // NOTE: flash attention was tried here for a Metal decode speedup but it
        // corrupted the q5_0 Apex decode — output collapsed into repetition loops
        // and long foreign-script token runs — so it stays OFF. The dynamic audio
        // context in transcribe_with_context is the safe speed win instead.
        let mut context_params = WhisperContextParameters::default();
        context_params.use_gpu(true);
        let context = WhisperContext::new_with_params(model_path, context_params)
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
        hotwords: &str,
    ) -> Result<String, String> {
        ensure_model_file(model_path)?;
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::Transcribe {
                model_path: model_path.to_owned(),
                language: language.to_owned(),
                samples: samples.to_vec(),
                hotwords: hotwords.to_owned(),
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
                // Live preview stays unbiased and fast; hotwords apply to the
                // final decode only.
                hotwords: String::new(),
                preview: true,
                response,
            })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, PREVIEW_DECODE_TIMEOUT, "generating a preview")?
    }

    fn detect_language(&self, model_path: &str, samples: &[f32]) -> Result<String, String> {
        ensure_model_file(model_path)?;
        let (response, result) = mpsc::channel();
        self.commands
            .send(ModelCommand::DetectLanguage {
                model_path: model_path.to_owned(),
                samples: samples.to_vec(),
                response,
            })
            .map_err(|_| "the ASR worker is unavailable".to_owned())?;
        await_worker_response(&result, PREVIEW_DECODE_TIMEOUT, "detecting the language")?
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
    hotwords: &str,
) -> Result<String, String> {
    let selected = model_path_for_language(Path::new(model_path), language);
    MODEL_REGISTRY.transcribe(&selected.to_string_lossy(), language, samples, hotwords)
}

pub(crate) fn transcribe_preview(
    model_path: &str,
    language: &str,
    samples: &[f32],
) -> Result<String, String> {
    let selected = model_path_for_language(Path::new(model_path), language);
    MODEL_REGISTRY.transcribe_preview(&selected.to_string_lossy(), language, samples)
}

/// Detects the spoken language via the warm whisper context, returning its ISO
/// code (e.g. "en", "hi"). Used only to route Auto mode to the correct fast engine.
pub(crate) fn detect_language(model_path: &str, samples: &[f32]) -> Result<String, String> {
    MODEL_REGISTRY.detect_language(model_path, samples)
}

/// The whisper model file that best fits `hint`, falling back to the user's
/// selected model when no specialist is installed.
///
/// Auto uses this to act on what its own detection heard, instead of sending
/// every Auto utterance to one model. `hint` accepts a mode name ("hindi") or
/// whisper's ISO code ("hi"); an empty hint means nothing is known and keeps the
/// general model.
pub(crate) fn whisper_model_for(model_path: &str, hint: &str) -> String {
    model_path_for_language(Path::new(model_path), hint)
        .to_string_lossy()
        .into_owned()
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
                hotwords,
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
                            &hotwords,
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
            ModelCommand::DetectLanguage {
                model_path,
                samples,
                response,
            } => {
                let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
                    cache.ensure(&model_path).and_then(|_| {
                        let model = cache
                            .get(&model_path)
                            .ok_or_else(|| "the offline model did not remain loaded".to_owned())?;
                        detect_language_with_context(&model.context, &samples)
                    })
                }));
                let result = outcome.unwrap_or_else(|_| {
                    cache.clear();
                    Err("the offline model failed during language detection".to_owned())
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

/// Detects the spoken language with whisper's encoder only (no decode), returning
/// its ISO code (e.g. "en", "hi"). Used to route Auto mode to the right fast
/// engine — English/European to Parakeet, Indian to IndicConformer — since neither
/// fast engine spans both families. This is a single encoder pass on the warm
/// whisper context, far cheaper than a full decode.
fn detect_language_with_context(
    context: &WhisperContext,
    samples: &[f32],
) -> Result<String, String> {
    let Some(samples) = prepared_decode_input(samples) else {
        return Ok(String::new());
    };
    let mut state = context.create_state().map_err(|error| error.to_string())?;
    state
        .pcm_to_mel(samples.as_ref(), available_threads() as usize)
        .map_err(|error| error.to_string())?;
    let (lang_id, _probs) = state
        .lang_detect(0, available_threads() as usize)
        .map_err(|error| error.to_string())?;
    Ok(whisper_rs::get_lang_str(lang_id).unwrap_or("en").to_owned())
}

/// Decodes an utterance of any length, one whisper window at a time.
///
/// Whisper encodes 30 s at a time and decides where the next window starts from
/// the timestamp it just emitted. Past one window that seeking goes wrong: a 45 s
/// Hinglish passage came back with 71 of its 145 spoken words and a whole clause
/// missing, and a 91 s clip duplicated text across the seam. Splitting the audio
/// at the speaker's own pauses (`audio::segment`) means whisper is never asked to
/// cross a seam, which measured better on both counts — word error over that
/// passage fell from 0.669 to 0.324.
fn transcribe_with_context(
    context: &WhisperContext,
    model_path: &Path,
    language: &str,
    samples: &[f32],
    hotwords: &str,
    preview: bool,
) -> Result<String, String> {
    // Degenerate input (empty, over-long, or NaN/Inf from an upstream resample)
    // can make whisper.cpp abort or return nothing useful. An empty transcript
    // is the correct, safe result for a buffer with no decodable audio.
    let Some(samples) = prepared_decode_input(samples) else {
        return Ok(String::new());
    };
    let samples = samples.as_ref();
    let mut pieces = Vec::new();
    for range in crate::audio::segment::split_at_pauses(samples, DECODE_SAMPLE_RATE) {
        let piece = decode_one_window(
            context,
            model_path,
            language,
            &samples[range],
            hotwords,
            preview,
        )?;
        let piece = piece.trim();
        if !piece.is_empty() {
            pieces.push(piece.to_owned());
        }
    }
    Ok(pieces.join(" "))
}

/// Decodes audio that already fits inside a single whisper window.
fn decode_one_window(
    context: &WhisperContext,
    model_path: &Path,
    language: &str,
    samples: &[f32],
    hotwords: &str,
    preview: bool,
) -> Result<String, String> {
    if samples.is_empty() {
        return Ok(String::new());
    }
    let mut state = context.create_state().map_err(|error| error.to_string())?;
    // Beam-2 matches the previously accepted (Wispr-comparable) quality while
    // keeping decode fast. Beam-5 was tried for extra accuracy but its added decode
    // cost made dictation slower overall for no clear quality gain, so it was
    // reverted. The dynamic audio context below is the real speed win and does not
    // touch decode quality. Whisper is now the fallback engine: the fast ONNX ASR
    // helper handles the primary path (see api::dictation and asr_client).
    let mut params = if preview {
        FullParams::new(SamplingStrategy::Greedy { best_of: 1 })
    } else {
        FullParams::new(SamplingStrategy::BeamSearch {
            beam_size: 2,
            patience: -1.0,
        })
    };
    params.set_translate(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    // Whisper decodes in 30 s windows, and it uses the timestamp token it emits
    // to decide where the next window starts. With timestamps off it cannot make
    // that decision, so it advances by a blind fixed stride and slices the audio
    // mid-word; the fragment left straddling the seam decodes as fluent garbage.
    // A 91 s count-to-ninety came back with "shambhar ... philadelphia ...
    // inambek" spliced in at the seam, and the identical hallucination appeared
    // under two different models, which is what ruled the model out as the cause.
    //
    // Single-segment plus no-timestamps stays on for the common case, where it is
    // both correct and the cheaper path: a dictation that fits inside one window
    // has no seam to get wrong.
    let fits_one_window = samples.len() < FULL_WINDOW_SAMPLES;
    params.set_no_timestamps(fits_one_window);
    params.set_single_segment(fits_one_window);
    params.set_n_threads(available_threads());
    // Shrink the encoder's audio context to the clip's real length. Whisper's
    // encoder otherwise always processes a full 30 s mel window (1500 ctx tokens)
    // no matter how short the utterance is, so a 3 s dictation pays ~10x the needed
    // encode cost. A margin keeps the tail intact; clips at/over 30 s fall back to
    // the model's full context. This is the largest single latency win for short
    // dictation, and it is what pays for the wider beam above.
    params.set_audio_ctx(dynamic_audio_ctx(samples.len()));
    params.set_suppress_blank(true);
    // Suppress non-speech tokens (music notes, [sounds], etc.). With the VAD hard
    // gate this closes the last of whisper.cpp's hallucination-on-noise hole
    // (swar.md §7).
    params.set_suppress_nst(true);
    params.set_no_speech_thold(0.60);
    params.set_temperature(0.0);
    params.set_temperature_inc(if preview { 0.0 } else { 0.2 });
    // Anti-repetition guards. A degenerate decode (wrong-language audio, noise,
    // a near-silent tail) can collapse into a token loop like "tit tit tit...".
    // whisper.cpp escapes that by re-decoding at a higher temperature when the
    // segment is too compressible (entropy_thold) or too improbable
    // (logprob_thold); the temperature_inc above supplies the escape steps.
    // Setting them explicitly guarantees the fallback is armed for final
    // dictation. Preview keeps a single fast greedy pass. no_context stops one
    // window's runaway tokens from seeding the next.
    params.set_no_context(true);
    if !preview {
        params.set_entropy_thold(2.4);
        params.set_logprob_thold(-1.0);
    }
    let decoding = language_decoding(language);
    params.set_language(decoding.whisper_language);
    params.set_detect_language(decoding.detect_language);
    // Bias the decoder toward the user's own vocabulary so proper nouns are
    // spelled correctly at the source ("Oynix", not "onyx"). This is the user's
    // words, not a hand-written romanisation prompt (which §7 bans), and it only
    // applies to the final decode. A concrete language mode may still carry a
    // built-in prompt; the hotwords take precedence when present.
    let hotwords = hotwords.trim();
    if !hotwords.is_empty() {
        params.set_initial_prompt(hotwords);
    } else if let Some(prompt) = decoding.initial_prompt {
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

/// Each explicit mode forces its language; Auto detects per utterance (swar.md
/// §7: "leave unset for Auto"). Forcing one language in Auto is wrong for a user
/// who alternates languages — a forced `hi` turns spoken English ("123 mic test")
/// into a Hindi-token hallucination loop, and a forced `en` destroys Hinglish.
/// Detection needs a healthy input level to be reliable (quiet audio is what
/// makes whisper.cpp misdetect Hindi as Urdu/Arabic), which the §4 gain stage now
/// provides. Whatever Auto detects, the later language stage romanises any
/// Devanagari, so English stays English and spoken Hindi comes out Roman.
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
        // Explicit Hinglish: the user is telling us it is Hindi-led code-switch,
        // so decode Hindi and romanise. `en` is banned here by §7.
        "hinglish" => LanguageDecoding {
            whisper_language: Some("hi"),
            initial_prompt: None,
            detect_language: false,
        },
        // Auto: language left unset so whisper.cpp auto-detects AND transcribes
        // (swar.md §7 / CLAUDE.md §11). `detect_language` MUST stay false —
        // setting it true triggers whisper.cpp's detection-ONLY mode, which
        // reports the language and returns an empty transcript.
        _ => LanguageDecoding {
            whisper_language: None,
            initial_prompt: None,
            detect_language: false,
        },
    }
}

const HINDI_MODEL_FILE: &str = "ggml-hi-small.bin";
/// Whisper-medium post-trained by Shunya Labs on Hindi-English code-switched
/// speech (shunyalabs/zero-stt-hinglish), converted to ggml and quantised q5_0.
/// Optional: absent means code-switched audio stays on the general multilingual
/// model, which still works, just less well.
const HINGLISH_MODEL_FILE: &str = "ggml-zero-stt-hinglish-q5_0.bin";

fn vad_model_next_to(model_path: &Path) -> Option<std::path::PathBuf> {
    let candidate = model_path.parent()?.join("ggml-silero-v6.2.0.bin");
    candidate.is_file().then_some(candidate)
}

fn sibling_model(model_path: &Path, file: &str) -> Option<std::path::PathBuf> {
    let candidate = model_path.parent()?.join(file);
    candidate.is_file().then_some(candidate)
}

/// Only explicit Hindi mode uses the monolingual Indic fine-tune (accurate
/// Devanagari). Kept as a pure predicate so routing is locked by a regression
/// test independent of which model files happen to be installed.
/// Accepts the ISO code too: Auto's routing hint arrives as whisper's own
/// detection output ("hi"), not as the mode name the settings screen uses.
fn uses_hindi_model(language: &str) -> bool {
    matches!(
        language.trim().to_ascii_lowercase().as_str(),
        "hindi" | "hi"
    )
}

/// Only explicit Hinglish takes the code-switch fine-tune.
///
/// Auto used to be routed here too, on the reasoning that it reaches whisper
/// only when the router saw an Indic language. That was wrong in the case that
/// matters: the fine-tune repeats short English utterances, returning
/// "hello this is svar hello this is svar" for a clip the general model
/// transcribes perfectly. Auto is the default mode and has to survive whatever
/// it is given, so it stays on the general multilingual model. A user who knows
/// they are code-switching can select Hinglish and get the specialist, which is
/// worth 0.696 to 0.174 on that route.
fn uses_hinglish_model(language: &str) -> bool {
    language.trim().eq_ignore_ascii_case("hinglish")
}

/// Whisper is the fallback engine (the fast ONNX helper is primary). Explicit
/// Hindi swaps to the monolingual Indic fine-tune; code-switched routes swap to
/// the Hinglish fine-tune when present, and otherwise stay on the user's
/// multilingual model, whose Devanagari output the language stage romanises.
///
/// Measured on the benchmark cases, the Hinglish fine-tune (whisper-medium,
/// q5_0) cuts Hinglish word error rate from 0.696 to 0.174, and it is *worse*
/// than the general model on monolingual Hindi (2.714), so the swap is
/// deliberately narrow.
fn model_path_for_language(model_path: &Path, language: &str) -> std::path::PathBuf {
    if uses_hindi_model(language) {
        if let Some(hindi) = sibling_model(model_path, HINDI_MODEL_FILE) {
            return hindi;
        }
    }
    if uses_hinglish_model(language) {
        if let Some(hinglish) = sibling_model(model_path, HINGLISH_MODEL_FILE) {
            return hinglish;
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

/// The encoder audio-context size to request for a clip of `sample_len` 16 kHz
/// samples. Whisper maps a full 30 s window to 1500 context tokens (one per
/// 320 samples / 20 ms), and always encodes the full window unless told otherwise.
/// Sizing the context to the real clip length — plus a safety margin so the tail
/// is never clipped — cuts encode cost roughly in proportion to how short the clip
/// is. A clip at or beyond the full window returns 0, whisper.cpp's "use the
/// model's full context" sentinel.
fn dynamic_audio_ctx(sample_len: usize) -> i32 {
    const SAMPLES_PER_CTX: usize = 320;
    const FULL_CTX: usize = 1500;
    const MARGIN_CTX: usize = 64;
    const MIN_CTX: usize = 128;
    const FULL_WINDOW_SAMPLES: usize = SAMPLES_PER_CTX * FULL_CTX; // 30 s at 16 kHz
    if sample_len >= FULL_WINDOW_SAMPLES {
        return 0;
    }
    ((sample_len / SAMPLES_PER_CTX) + MARGIN_CTX).clamp(MIN_CTX, FULL_CTX) as i32
}

fn available_threads() -> i32 {
    thread::available_parallelism()
        .map(|count| count.get().saturating_sub(1).clamp(1, 8) as i32)
        .unwrap_or(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Opt-in diagnostic: loads the installed whisper model and reports the language
    // it detects for a 16 kHz mono Int16 WAV. Used to validate that Auto routing
    // distinguishes English (-> Parakeet) from Indian speech (-> IndicConformer).
    // No-ops unless both env vars point at real files, so CI never runs it.
    #[test]
    fn detect_language_on_env_wav() {
        let (Ok(model), Ok(wav)) = (
            std::env::var("SWAR_DETECT_MODEL"),
            std::env::var("SWAR_DETECT_WAV"),
        ) else {
            return;
        };
        let bytes = std::fs::read(&wav).expect("read wav");
        let samples: Vec<f32> = bytes[44..]
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
            .collect();
        let code = detect_language(&model, &samples).expect("detect");
        println!("DETECTED[{wav}] = {code}");
    }

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
    fn audio_ctx_shrinks_for_short_clips_and_falls_back_for_long_ones() {
        // A ~3 s clip needs far less than the full 1500-token window, so the
        // encoder does proportionally less work (the main short-dictation win).
        let three_seconds = 16_000 * 3;
        let ctx = dynamic_audio_ctx(three_seconds);
        assert!(
            ctx > 0 && ctx < 1500,
            "3 s should shrink the context: {ctx}"
        );
        // 3 s == 150 ctx tokens + 64 margin.
        assert_eq!(ctx, (three_seconds / 320 + 64) as i32);

        // Very short clips never drop below the safety floor, so quality holds.
        assert_eq!(dynamic_audio_ctx(16_000 / 10), 128);
        assert_eq!(dynamic_audio_ctx(0), 128);

        // A clip at/over the full 30 s window returns 0 == "use the full context".
        assert_eq!(dynamic_audio_ctx(16_000 * 30), 0);
        assert_eq!(dynamic_audio_ctx(16_000 * 45), 0);

        // The result is always a legal whisper.cpp audio-context value.
        for seconds in [1, 2, 5, 10, 20, 29] {
            let value = dynamic_audio_ctx(16_000 * seconds);
            assert!((128..=1500).contains(&value), "{seconds}s -> {value}");
        }
    }

    #[test]
    fn explicit_modes_force_their_language_and_auto_leaves_it_unset() {
        // Explicit modes pin their language; `en` is banned for Hinglish (§7).
        assert_eq!(language_decoding("english").whisper_language, Some("en"));
        assert_eq!(language_decoding("hindi").whisper_language, Some("hi"));
        assert_eq!(language_decoding("hinglish").whisper_language, Some("hi"));

        // Auto leaves the language unset so whisper.cpp auto-detects AND
        // transcribes (§7: "leave unset for Auto"). detect_language MUST stay
        // false — true is whisper.cpp's detection-ONLY mode and returns an empty
        // transcript (CLAUDE.md §11).
        let auto = language_decoding("automatic");
        assert_eq!(auto.whisper_language, None);
        assert!(
            !auto.detect_language,
            "Auto must not use detection-only mode"
        );

        // No mode enables detection-only mode or biases the decoder with a prompt.
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
    fn only_explicit_hindi_uses_the_monolingual_indic_model() {
        // Regression: Hinglish was once routed through the Hindi-only fine-tune,
        // which mangled English words ("complete" -> "kanplit"). Only explicit
        // Hindi may request the Indic model; every code-switch-capable mode stays
        // on the multilingual model. Kept file-independent via the pure predicate.
        assert!(uses_hindi_model("hindi"));
        assert!(uses_hindi_model("Hindi"));
        for mode in ["hinglish", "automatic", "english", "", "auto"] {
            assert!(
                !uses_hindi_model(mode),
                "{mode:?} must stay on the multilingual model"
            );
        }
    }

    #[test]
    fn whisper_fallback_routes_each_language_to_its_best_installed_model() {
        use std::fs;
        let dir = std::env::temp_dir().join(format!("swar-fallback-route-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("temp dir");
        let selected = dir.join("ggml-small-q5_1.bin");
        fs::write(&selected, b"x").expect("write base");

        // With no fine-tune installed, every mode stays on the selected
        // multilingual model; the language stage romanises its Devanagari.
        for mode in ["hinglish", "automatic", "auto", "english", ""] {
            assert_eq!(
                model_path_for_language(&selected, mode),
                selected,
                "{mode:?}"
            );
        }

        // Only explicit Hindi swaps to the Indic fine-tune when it sits next to it.
        let hindi = dir.join(HINDI_MODEL_FILE);
        fs::write(&hindi, b"x").expect("write hindi");
        assert_eq!(model_path_for_language(&selected, "hindi"), hindi);
        assert_eq!(model_path_for_language(&selected, "hinglish"), selected);

        // Explicit Hinglish takes the fine-tune once installed. Measured on the
        // benchmark cases it cuts Hinglish word error rate from 0.696 to 0.174,
        // so this swap is worth its 514 MB.
        let hinglish = dir.join(HINGLISH_MODEL_FILE);
        fs::write(&hinglish, b"x").expect("write hinglish");
        assert_eq!(model_path_for_language(&selected, "hinglish"), hinglish);

        // Every other mode keeps the general model, Auto included. The fine-tune
        // repeats short English ("hello this is svar hello this is svar" for a
        // clip the general model gets exactly right), and Auto is the default
        // mode, so it has to survive whatever it is handed. On monolingual Hindi
        // the same fine-tune measured 2.714 against the general model's 0.429.
        for mode in ["automatic", "auto", "", "english"] {
            assert_eq!(
                model_path_for_language(&selected, mode),
                selected,
                "{mode:?}"
            );
        }
        assert_eq!(model_path_for_language(&selected, "hindi"), hindi);

        let _ = fs::remove_dir_all(&dir);
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
