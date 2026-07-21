use std::{
    fs,
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, LazyLock, Mutex,
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use crate::{
    api::personalization,
    asr::model_registry,
    audio::{capture_engine, gain, resample, speech},
    dictation::{
        coordinator::DictationCoordinator,
        state_machine::{DictationState, DictationStateMachine, DictationTransition},
    },
    enhancement,
    frb_generated::StreamSink,
    insertion,
    storage::{self, NewDictation},
    text_cleanup,
};
use cpal::{
    traits::{DeviceTrait, HostTrait},
    Device,
};
use directories::ProjectDirs;
use flutter_rust_bridge::frb;
use uuid::Uuid;

/// Minimum spacing between audio-meter events (~25 Hz, within the <=30 Hz UI
/// budget). Bounds the Rust->Dart stream regardless of the capture level rate.
const MINIMUM_LEVEL_INTERVAL_MS: u64 = 40;

/// How long finish/cancel waits for the preview worker to exit before detaching
/// it, so a preview decode in flight cannot block completion (the decode itself
/// is separately bounded by the ASR preview watchdog).
const PREVIEW_JOIN_TIMEOUT: Duration = Duration::from_secs(2);

static ACTIVE_CAPTURE: Mutex<Option<ActiveCapture>> = Mutex::new(None);
static COORDINATOR: LazyLock<Mutex<DictationCoordinator>> =
    LazyLock::new(|| Mutex::new(DictationCoordinator::default()));

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DictationLifecycleState {
    Idle,
    Preparing,
    Recording,
    Finalising,
    Transcribing,
    Cleaning,
    Enhancing,
    Inserting,
    CopiedFallback,
    Completed,
    Cancelled,
    Failed,
}

impl From<DictationState> for DictationLifecycleState {
    fn from(value: DictationState) -> Self {
        match value {
            DictationState::Idle => Self::Idle,
            DictationState::Preparing => Self::Preparing,
            DictationState::Recording => Self::Recording,
            DictationState::Finalising => Self::Finalising,
            DictationState::Transcribing => Self::Transcribing,
            DictationState::Cleaning => Self::Cleaning,
            DictationState::Enhancing => Self::Enhancing,
            DictationState::Inserting => Self::Inserting,
            DictationState::CopiedFallback => Self::CopiedFallback,
            DictationState::Completed => Self::Completed,
            DictationState::Cancelled => Self::Cancelled,
            DictationState::Failed => Self::Failed,
        }
    }
}

#[derive(Clone, Debug)]
pub enum DictationEventKind {
    StateChanged,
    Preparing,
    Recording,
    AudioLevel,
    Finalising,
    Cancelled,
    Failed,
    PartialTranscript,
}

#[derive(Clone, Debug)]
pub struct DictationEvent {
    pub session_id: String,
    pub kind: DictationEventKind,
    pub audio_level: Option<f64>,
    pub message: Option<String>,
    pub timestamp_ms: u64,
    pub previous_state: DictationLifecycleState,
    pub current_state: DictationLifecycleState,
    pub reason: String,
    pub partial_text: Option<String>,
}

#[derive(Clone)]
pub struct DictationSessionConfig {
    pub model_path: String,
    pub microphone_id: String,
    pub language: String,
    pub writing_mode: String,
    pub source_application: String,
    pub paste_automatically: bool,
    pub restore_clipboard: bool,
    pub maximum_seconds: u32,
    pub enable_live_preview: bool,
    pub enhancement_provider: String,
    pub provider_endpoint: String,
    pub provider_model: String,
    pub provider_api_key: String,
    /// True when the focused field is a secure/password field. The dictation
    /// still runs and inserts, but nothing is written to history (privacy P0).
    pub is_sensitive: bool,
    /// The text already in the focused field, split at the caret. Used only as
    /// reference context for the on-device cleanup LLM, never sent to a BYOK
    /// provider, and never captured at all for a secure field.
    pub cursor_text_before: String,
    pub cursor_text_after: String,
}

// Manual Debug so a stray `{:?}` (in a log line or panic message) can never leak
// the BYOK provider key. Every other field is shown as usual.
impl std::fmt::Debug for DictationSessionConfig {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("DictationSessionConfig")
            .field("model_path", &self.model_path)
            .field("microphone_id", &self.microphone_id)
            .field("language", &self.language)
            .field("writing_mode", &self.writing_mode)
            .field("source_application", &self.source_application)
            .field("paste_automatically", &self.paste_automatically)
            .field("restore_clipboard", &self.restore_clipboard)
            .field("maximum_seconds", &self.maximum_seconds)
            .field("enable_live_preview", &self.enable_live_preview)
            .field("enhancement_provider", &self.enhancement_provider)
            .field("provider_endpoint", &self.provider_endpoint)
            .field("provider_model", &self.provider_model)
            .field(
                "provider_api_key",
                &if self.provider_api_key.is_empty() {
                    "<none>"
                } else {
                    "<redacted>"
                },
            )
            .field("is_sensitive", &self.is_sensitive)
            // The user's own document text: never printed, only its size.
            .field("cursor_text_before", &self.cursor_text_before.len())
            .field("cursor_text_after", &self.cursor_text_after.len())
            .finish()
    }
}

#[derive(Clone, Debug)]
pub struct DictationCompletion {
    pub session_id: String,
    pub raw_text: String,
    pub final_text: String,
    pub audio_duration_ms: u64,
    pub processing_duration_ms: u64,
    pub insertion_status: String,
    pub insertion_method: String,
}

#[derive(Clone, Debug)]
pub struct MicrophoneDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_built_in: bool,
}

struct ActiveCapture {
    id: String,
    config: DictationSessionConfig,
    sample_rate: u32,
    started_at: Instant,
    dropped_samples_at_start: u64,
    stream_errors_at_start: u64,
    preview_running: Arc<AtomicBool>,
    preview_exited: Arc<AtomicBool>,
    preview_worker: Option<thread::JoinHandle<()>>,
    sink: StreamSink<DictationEvent>,
    lifecycle: DictationStateMachine,
}

/// Lists the audio inputs visible to CoreAudio/WASAPI through CPAL.
pub fn list_microphones() -> Result<Vec<MicrophoneDevice>, String> {
    let host = cpal::default_host();
    let default_name = host.default_input_device().map(|device| device.to_string());
    let devices = host.input_devices().map_err(|error| error.to_string())?;
    let mut microphones = devices
        .enumerate()
        .map(|(index, device)| {
            let name = device.to_string();
            let device_id = device
                .id()
                .map(|id| id.to_string())
                .unwrap_or_else(|_| format!("input-{index}"));
            Ok(MicrophoneDevice {
                id: device_id,
                is_default: default_name.as_deref() == Some(name.as_str()),
                is_built_in: is_builtin_microphone_name(&name),
                name,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    microphones.sort_by_key(|device| (!device.is_built_in, !device.is_default));
    Ok(microphones)
}

/// Begins a single native recording session. Raw PCM remains in Rust.
pub fn start_dictation_session(
    config: DictationSessionConfig,
    sink: StreamSink<DictationEvent>,
) -> Result<String, String> {
    let mut active = ACTIVE_CAPTURE
        .lock()
        .map_err(|_| "dictation session lock poisoned".to_owned())?;
    if active.is_some() {
        return Err("another dictation session is already active".to_owned());
    }

    if config.model_path.trim().is_empty() || !Path::new(&config.model_path).is_file() {
        return Err("model_not_installed: choose an offline Whisper model in Settings".to_owned());
    }
    model_registry::prepare(&config.model_path)?;

    let session_id = Uuid::new_v4().to_string();
    COORDINATOR
        .lock()
        .map_err(|_| "dictation coordinator lock poisoned".to_owned())?
        .reserve_recording(&session_id)?;
    // From here on the slot is reserved; the guard frees it on any early return
    // or panic. It is disarmed only once the session is fully armed and handed
    // back to the caller, after which `finish`/`cancel` own the release.
    let reservation = ReservationGuard::new(session_id.clone());
    let mut lifecycle = DictationStateMachine::new();
    let preparing = lifecycle
        .transition(DictationState::Preparing, "shortcut activated")
        .map_err(|error| error.to_string())?;
    emit_transition(&sink, &session_id, preparing, None);

    let host = cpal::default_host();
    let device = match select_input_device(&host, &config.microphone_id) {
        Ok(device) => device,
        Err(error) => {
            fail_start(&mut lifecycle, &sink, &session_id, &error);
            return Err(error);
        }
    };
    let device_id = device
        .id()
        .map(|id| id.to_string())
        .unwrap_or_else(|_| device.to_string());
    let level_sink = sink.clone();
    let level_session_id = session_id.clone();
    // Throttle audio-meter events to <=30 Hz at the emission point, so the
    // Rust->Dart stream cannot accumulate an unbounded backlog if the UI
    // isolate falls behind during a long recording (spec: AudioLevel <=30 Hz).
    let last_level_ms = Arc::new(AtomicU64::new(0));
    let capture_start = match capture_engine::begin_capture(
        &device,
        device_id,
        session_id.clone(),
        config.maximum_seconds,
        Arc::new(move |rms| {
            let now = monotonic_timestamp_ms();
            if now.saturating_sub(last_level_ms.load(Ordering::Relaxed)) < MINIMUM_LEVEL_INTERVAL_MS
            {
                return;
            }
            last_level_ms.store(now, Ordering::Relaxed);
            let _ = level_sink.add(DictationEvent {
                session_id: level_session_id.clone(),
                kind: DictationEventKind::AudioLevel,
                audio_level: Some(rms),
                message: None,
                timestamp_ms: now,
                previous_state: DictationState::Recording.into(),
                current_state: DictationState::Recording.into(),
                reason: "audio meter".to_owned(),
                partial_text: None,
            });
        }),
    ) {
        Ok(start) => start,
        Err(error) => {
            fail_start(&mut lifecycle, &sink, &session_id, &error);
            return Err(error);
        }
    };
    let recording = lifecycle
        .transition(DictationState::Recording, "microphone ready")
        .map_err(|error| error.to_string())?;
    emit_transition(&sink, &session_id, recording, None);
    let preview_running = Arc::new(AtomicBool::new(config.enable_live_preview));
    let preview_exited = Arc::new(AtomicBool::new(false));
    let preview_worker = if config.enable_live_preview {
        match spawn_preview_worker(
            session_id.clone(),
            config.model_path.clone(),
            config.language.clone(),
            sink.clone(),
            preview_running.clone(),
            preview_exited.clone(),
        ) {
            Ok(handle) => Some(handle),
            Err(_) => {
                // Live preview is optional. A thread-spawn failure must degrade
                // to no-preview, never panic (which would poison ACTIVE_CAPTURE
                // and permanently disable dictation).
                preview_running.store(false, Ordering::Release);
                None
            }
        }
    } else {
        None
    };

    *active = Some(ActiveCapture {
        id: session_id.clone(),
        config,
        sample_rate: capture_start.sample_rate,
        started_at: Instant::now(),
        dropped_samples_at_start: capture_start.dropped_samples_at_start,
        stream_errors_at_start: capture_start.stream_errors_at_start,
        preview_running,
        preview_exited,
        preview_worker,
        sink,
        lifecycle,
    });
    // The session is now armed; finish/cancel own the reservation from here.
    reservation.disarm();
    Ok(session_id)
}

/// Stops capture, transcribes locally with whisper.cpp, cleans, inserts, and persists.
pub fn finish_dictation_session(session_id: String) -> Result<DictationCompletion, String> {
    // Releases the coordinator slot on every exit path — including an early `?`
    // return or a panic inside transcription/insertion — so a failure can never
    // wedge future dictations.
    let _reservation = ReservationGuard::new(session_id.clone());
    let mut capture = take_capture(&session_id)?;
    COORDINATOR
        .lock()
        .map_err(|_| "dictation coordinator lock poisoned".to_owned())?
        .begin_post_processing(&session_id)?;
    transition_capture(
        &mut capture,
        DictationState::Finalising,
        "shortcut released",
    )?;
    let result = finish_capture(&mut capture);
    match result {
        Ok(completion) => {
            transition_capture(&mut capture, DictationState::Completed, "history committed")?;
            transition_capture(&mut capture, DictationState::Idle, "session released")?;
            Ok(completion)
        }
        Err(error) => {
            let _ = transition_capture(&mut capture, DictationState::Failed, error.clone());
            Err(error)
        }
    }
}

fn finish_capture(capture: &mut ActiveCapture) -> Result<DictationCompletion, String> {
    record_dictation_stage("capture");
    stop_preview(capture);
    let captured_result = capture_engine::finish_capture(
        &capture.id,
        capture.dropped_samples_at_start,
        capture.stream_errors_at_start,
    );
    // The audio buffer is now owned, so close the microphone immediately — the
    // OS recording indicator clears while transcription and insertion run. The
    // mic is opened again only for the next dictation (lazily, in begin_capture).
    let _ = capture_engine::release();
    let mut captured = captured_result.map_err(|_| dictation_stage_error("capture"))?;
    if captured.is_empty() {
        return Err(dictation_stage_error("capture_empty"));
    }

    let processing_started = Instant::now();
    let mono_16khz = resample::to_sample_rate(&captured, capture.sample_rate, 16_000);
    // The raw capture buffer holds up to several minutes of dictation PCM and is
    // not needed after resampling. Scrub it now rather than waiting for the
    // allocator to hand the pages to another process (privacy guarantee).
    captured.iter_mut().for_each(|sample| *sample = 0.0);
    // Present the model a consistent level (swar.md §4): quiet input gets dropped
    // words, hot input gets garbled. Normalize toward -20 dBFS RMS with a soft
    // peak limiter before VAD. `gain_metrics` are privacy-safe diagnostics.
    let (mono_16khz, gain_metrics) = gain::normalize(&mono_16khz);
    record_dictation_levels(&gain_metrics);
    record_dictation_stage("speech_detection");
    let speech = speech::retain_probable_speech(&mono_16khz, 16_000);
    if speech.samples.is_empty() {
        return Err(dictation_stage_error("speech_detection"));
    }
    transition_capture(
        capture,
        DictationState::Transcribing,
        "audio drained and resampled",
    )?;
    record_dictation_stage("transcription");
    // Resolve the engine language. The two fast engines do not span both language
    // families (Parakeet is English/European, IndicConformer is Indian), so Auto
    // must first detect which family was spoken and route accordingly — otherwise
    // English spoken in Auto would be decoded as phonetic Hindi.
    // Swar recognises English. Parakeet is the engine: it decodes a 38 s
    // utterance in 4.3 s at zero word error on the reference passage, roughly
    // twice as fast as whisper and without whisper's 30 s window seam. Whisper
    // remains only as the safety net for when the helper or its model is
    // missing or errors, so recognition never hard-fails.
    let raw_text = match crate::asr_client::transcribe(&speech.samples, ASR_LANGUAGE) {
        Ok(text) if transcript_contains_speech(&text) => text,
        _ => {
            // Bias whisper toward the user's own proper nouns at the source (§7).
            let hotwords = personalization::hotword_prompt();
            model_registry::transcribe(
                &capture.config.model_path,
                ASR_LANGUAGE,
                &speech.samples,
                &hotwords,
            )
            .map_err(|_| dictation_stage_error("transcription"))?
        }
    };
    if !transcript_contains_speech(&raw_text) {
        return Err(dictation_stage_error("transcription_empty"));
    }
    let output_text = raw_text.clone();
    record_dictation_stage("cleanup");
    transition_capture(capture, DictationState::Cleaning, "final transcript ready")?;
    let personalized_raw = personalization::apply_vocabulary(&output_text);
    let clean_text =
        text_cleanup::clean_transcript(&personalized_raw, &capture.config.writing_mode);
    if clean_text.trim().is_empty() {
        return Err(dictation_stage_error("cleanup_empty"));
    }
    // When the on-device cleanup LLM is installed, use it for the default
    // "local" route (and the explicit "embedded-llm" route): it does Wispr-style
    // context cleanup the deterministic editor cannot ("mic" vs "Mike",
    // punctuation, casing). BYOK and local-llm server routes are left exactly as
    // configured. The GGUF path is resolved here so Flutter never needs to know
    // it. If the helper or model is not present, the enhancer degrades to the
    // deterministic editor, so this is safe whether or not cleanup is installed.
    let embedded_llm_path = crate::api::models::embedded_llm_model_path();
    let configured_provider = capture.config.enhancement_provider.trim();
    let use_embedded = embedded_llm_path.is_some()
        && (configured_provider.is_empty()
            || configured_provider.eq_ignore_ascii_case("local")
            || configured_provider.eq_ignore_ascii_case("embedded")
            || configured_provider.eq_ignore_ascii_case("embedded-llm"));
    let embedded_model_string = embedded_llm_path
        .as_ref()
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default();
    let (enhancement_provider, enhancement_model): (&str, &str) = if use_embedded {
        ("embedded-llm", embedded_model_string.as_str())
    } else {
        (
            capture.config.enhancement_provider.as_str(),
            capture.config.provider_model.as_str(),
        )
    };
    // Assembled per dictation because history and the focused field both move.
    // A secure field contributes nothing: its text is never captured, and no
    // history exists for it to draw on either.
    let local_context = if capture.config.is_sensitive {
        String::new()
    } else {
        crate::context::build(crate::context::CursorContext {
            before: &capture.config.cursor_text_before,
            after: &capture.config.cursor_text_after,
        })
    };
    let enhancement = enhancement::enhance_transcript(
        &personalized_raw,
        &clean_text,
        &capture.config.writing_mode,
        &capture.config.source_application,
        &local_context,
        enhancement::EnhancementProviderConfig {
            provider: enhancement_provider,
            endpoint: &capture.config.provider_endpoint,
            model: enhancement_model,
            api_key: &capture.config.provider_api_key,
        },
    );
    if enhancement.routed {
        transition_capture(
            capture,
            DictationState::Enhancing,
            if enhancement.validation_fallback {
                "enhancement rejected by protected-token validator"
            } else if enhancement.applied {
                "local enhancement applied"
            } else {
                "local enhancement kept deterministic text"
            },
        )?;
    }
    let final_text = enhancement.text;
    record_dictation_stage("insertion");
    transition_capture(capture, DictationState::Inserting, "cleanup completed")?;
    let insertion = insertion::insert_with_clipboard(
        &capture.id,
        &final_text,
        capture.config.paste_automatically,
        capture.config.restore_clipboard,
    )
    .map_err(|_| dictation_stage_error("insertion"))?;
    if insertion.status != "inserted" && capture.config.paste_automatically {
        transition_capture(
            capture,
            DictationState::CopiedFallback,
            "automatic insertion unavailable",
        )?;
    }
    let processing_duration_ms = processing_started.elapsed().as_millis() as u64;
    let audio_duration_ms = capture.started_at.elapsed().as_millis() as u64;
    let created_at_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| dictation_stage_error("clock"))?
        .as_millis() as i64;

    // Privacy P0: a dictation into a secure (password) field is inserted for the
    // user but MUST NOT be persisted. Skip the history write entirely — no raw,
    // clean, or final text touches SQLite — and record only a privacy-safe stage
    // marker. (No text was ever going to storage, so there is nothing to redact.)
    if should_write_history(capture.config.is_sensitive) {
        record_dictation_stage("history");
        storage::save_dictation(NewDictation {
            id: &capture.id,
            created_at_ms,
            raw_text: &raw_text,
            cleaned_text: &final_text,
            final_text: &final_text,
            language: &capture.config.language,
            writing_mode: &capture.config.writing_mode,
            // Foreground app context is ephemeral and is never persisted.
            source_application: "Desktop",
            audio_duration_ms,
            speech_duration_ms: speech.speech_duration_ms,
            processing_duration_ms,
            asr_engine: "whisper.cpp",
            asr_model_id: Path::new(&capture.config.model_path)
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("whisper-model"),
            insertion_status: insertion.status,
            insertion_method: insertion.method,
        })
        .map_err(|_| dictation_stage_error("history"))?;
        // Best-effort: bound local history and learning data. A retention failure
        // must never fail a completed dictation.
        let _ = storage::enforce_history_retention();
    } else {
        record_dictation_stage("sensitive_no_history");
    }
    record_dictation_stage("completed");

    Ok(DictationCompletion {
        session_id: capture.id.clone(),
        raw_text,
        final_text,
        audio_duration_ms,
        processing_duration_ms,
        insertion_status: insertion.status.to_owned(),
        insertion_method: insertion.method.to_owned(),
    })
}

/// Returns a privacy-safe failure code. The stage is a hard-coded internal
/// label, never dictated text, clipboard contents, audio, or a provider error.
fn dictation_stage_error(stage: &'static str) -> String {
    record_dictation_stage(stage);
    format!("dictation_stage:{stage}")
}

/// Persists only a static pipeline stage for local troubleshooting. This file
/// never contains recognised text, clipboard contents, audio, or error text.
/// Whether a completed dictation may be written to history. A dictation into a
/// secure (password) field is inserted for the user but never persisted, so no
/// raw/clean/final text can reach SQLite (privacy P0).
fn should_write_history(is_sensitive: bool) -> bool {
    !is_sensitive
}

fn record_dictation_stage(stage: &'static str) {
    let Some(directories) = ProjectDirs::from("dev", "Swar", "Swar") else {
        return;
    };
    let path = directories.data_local_dir().join("last_dictation_stage");
    let _ = fs::write(path, stage.as_bytes());
}

/// Writes the four §4 gain metrics for the last utterance to a privacy-safe
/// diagnostics file. It holds only levels (peak/RMS dBFS, clipped %, applied
/// gain) — never audio, text, or clipboard — so an "audio quality" report can be
/// triaged against swar.md §0 without ever storing what was said.
fn record_dictation_levels(metrics: &crate::audio::gain::GainMetrics) {
    let Some(directories) = ProjectDirs::from("dev", "Swar", "Swar") else {
        return;
    };
    let path = directories.data_local_dir().join("last_dictation_levels");
    let line = format!(
        "peak_dbfs={:.1} rms_dbfs={:.1} clipped_pct={:.2} applied_gain_db={:.1}",
        metrics.peak_dbfs, metrics.rms_dbfs, metrics.clipped_pct, metrics.applied_gain_db
    );
    let _ = fs::write(path, line.as_bytes());
}

/// Cancels the active capture and discards all PCM without writing history.
pub fn cancel_dictation_session(session_id: String) -> Result<(), String> {
    // The guard frees the coordinator slot even if `cancel_capture` or a
    // transition returns an error partway through cancellation.
    let _reservation = ReservationGuard::new(session_id.clone());
    let mut capture = take_capture(&session_id)?;
    transition_capture(&mut capture, DictationState::Cancelled, "user cancelled")?;
    stop_preview(&mut capture);
    capture_engine::cancel_capture(&session_id)?;
    // Close the microphone on cancel too, so the OS indicator never lingers.
    let _ = capture_engine::release();
    transition_capture(&mut capture, DictationState::Idle, "session released")?;
    Ok(())
}

#[frb(sync)]
pub fn offline_model_is_ready(model_path: String) -> bool {
    !model_path.trim().is_empty() && Path::new(&model_path).is_file()
}

/// Loads the selected model on the dedicated ASR worker before the first dictation.
pub fn prepare_dictation_engine(model_path: String) -> Result<bool, String> {
    let already_loaded =
        model_registry::prepare(&model_path).map(|status| status.already_loaded)?;
    // Cleanup "just works" with no setup: when the model is present, warm the
    // helper off-thread so the first dictation does not pay the ~2 GB load; when
    // it is absent, download it once in the background (cleanup stays on the
    // instant deterministic editor until it lands). Both are best-effort and
    // non-blocking, so neither can delay or fail engine preparation.
    match crate::api::models::embedded_llm_model_path() {
        Some(path) => {
            std::thread::spawn(move || {
                let _ = crate::llm_client::prepare(
                    &path.to_string_lossy(),
                    crate::enhancement::cleanup_system_prompt(),
                );
            });
        }
        None => crate::api::models::ensure_embedded_llm_model_download(),
    }
    // Fetch the default English engine (Parakeet) once in the background too.
    // Self-guarded and non-blocking: recognition stays on whisper until it lands.
    // The Indian-languages pack (IndicConformer) is opt-in from Settings, so it is
    // NOT downloaded here.
    crate::api::models::ensure_parakeet_download();
    // Warm the fast ASR engines off-thread so the first dictation does not pay
    // their cold load (~2-3 s for Parakeet). Best-effort and non-blocking.
    std::thread::spawn(crate::asr_client::warm);
    Ok(already_loaded)
}

/// Starts CoreAudio/WASAPI before the first shortcut so native pre-roll is
/// available from the first dictation without moving PCM into Dart.
pub fn prepare_audio_capture(microphone_id: String) -> Result<u32, String> {
    let host = cpal::default_host();
    let device = select_input_device(&host, &microphone_id)?;
    let device_id = device
        .id()
        .map(|id| id.to_string())
        .unwrap_or_else(|_| device.to_string());
    capture_engine::prepare(&device, device_id)
}

/// Releases the warm model without stopping the dedicated ASR worker.
pub fn release_dictation_engine() -> Result<(), String> {
    model_registry::unload()?;
    // Stop the cleanup helper too, freeing its ~2 GB of weights. The helper owns
    // llama.cpp in its own process, so its Metal teardown happens there; here we
    // just end it. Best-effort: never fail shutdown on it.
    let _ = crate::llm_client::shutdown();
    capture_engine::release()
}

fn take_capture(session_id: &str) -> Result<ActiveCapture, String> {
    let mut active = ACTIVE_CAPTURE
        .lock()
        .map_err(|_| "dictation session lock poisoned".to_owned())?;
    let capture = active
        .take()
        .ok_or_else(|| "no dictation session is active".to_owned())?;
    if capture.id != session_id {
        *active = Some(capture);
        return Err("the requested dictation session is not active".to_owned());
    }
    Ok(capture)
}

fn spawn_preview_worker(
    session_id: String,
    model_path: String,
    language: String,
    sink: StreamSink<DictationEvent>,
    running: Arc<AtomicBool>,
    exited: Arc<AtomicBool>,
) -> Result<thread::JoinHandle<()>, String> {
    thread::Builder::new()
        .name(format!("swar-preview-{session_id}"))
        .spawn(move || {
            let mut elapsed = Duration::ZERO;
            let mut previous = String::new();
            while running.load(Ordering::Acquire) {
                thread::sleep(Duration::from_millis(100));
                elapsed += Duration::from_millis(100);
                if elapsed < Duration::from_millis(1_000) {
                    continue;
                }
                elapsed = Duration::ZERO;
                let Ok((samples, sample_rate)) = capture_engine::snapshot(&session_id) else {
                    break;
                };
                if samples.len() < sample_rate as usize * 4 / 5 {
                    continue;
                }
                let mono_16khz = resample::to_sample_rate(&samples, sample_rate, 16_000);
                let Ok(partial) =
                    model_registry::transcribe_preview(&model_path, &language, &mono_16khz)
                else {
                    continue;
                };
                if partial.is_empty()
                    || partial == previous
                    || !transcript_contains_speech(&partial)
                    || is_degenerate_preview(&partial)
                {
                    continue;
                }
                previous.clone_from(&partial);
                // The decode above takes seconds, and the speaker may have
                // stopped during it. Re-check before emitting: a preview that
                // arrives after the session has left Recording describes a state
                // that no longer exists.
                if !running.load(Ordering::Acquire) {
                    break;
                }
                let _ = sink.add(DictationEvent {
                    session_id: session_id.clone(),
                    kind: DictationEventKind::PartialTranscript,
                    audio_level: None,
                    message: None,
                    timestamp_ms: monotonic_timestamp_ms(),
                    previous_state: DictationState::Recording.into(),
                    current_state: DictationState::Recording.into(),
                    reason: "tentative local preview".to_owned(),
                    partial_text: Some(partial),
                });
            }
            exited.store(true, Ordering::Release);
        })
        .map_err(|error| error.to_string())
}

fn stop_preview(capture: &mut ActiveCapture) {
    capture.preview_running.store(false, Ordering::Release);
    if let Some(worker) = capture.preview_worker.take() {
        // The preview worker may be mid-decode. Its decode is already bounded by
        // the ASR preview watchdog, so wait briefly for a clean exit and then
        // detach rather than block finish/cancel (and the coordinator) on it.
        let deadline = Instant::now() + PREVIEW_JOIN_TIMEOUT;
        while !capture.preview_exited.load(Ordering::Acquire) && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(5));
        }
        if capture.preview_exited.load(Ordering::Acquire) {
            let _ = worker.join();
        }
    }
}

fn transition_capture(
    capture: &mut ActiveCapture,
    state: DictationState,
    reason: impl Into<String>,
) -> Result<(), String> {
    let transition = capture
        .lifecycle
        .transition(state, reason)
        .map_err(|error| error.to_string())?;
    emit_transition(&capture.sink, &capture.id, transition, None);
    Ok(())
}

fn emit_transition(
    sink: &StreamSink<DictationEvent>,
    session_id: &str,
    transition: DictationTransition,
    message: Option<String>,
) {
    let kind = event_kind_for_state(transition.current);
    let _ = sink.add(DictationEvent {
        session_id: session_id.to_owned(),
        kind,
        audio_level: None,
        message,
        timestamp_ms: monotonic_timestamp_ms(),
        previous_state: transition.previous.into(),
        current_state: transition.current.into(),
        reason: transition.reason,
        partial_text: None,
    });
}

fn event_kind_for_state(state: DictationState) -> DictationEventKind {
    match state {
        DictationState::Preparing => DictationEventKind::Preparing,
        DictationState::Recording => DictationEventKind::Recording,
        DictationState::Finalising
        | DictationState::Transcribing
        | DictationState::Cleaning
        | DictationState::Enhancing
        | DictationState::Inserting
        | DictationState::CopiedFallback
        | DictationState::Completed
        | DictationState::Idle => DictationEventKind::Finalising,
        DictationState::Cancelled => DictationEventKind::Cancelled,
        DictationState::Failed => DictationEventKind::Failed,
    }
}

fn fail_start(
    lifecycle: &mut DictationStateMachine,
    sink: &StreamSink<DictationEvent>,
    session_id: &str,
    message: &str,
) {
    if let Ok(transition) = lifecycle.transition(DictationState::Failed, message) {
        emit_transition(sink, session_id, transition, Some(message.to_owned()));
    }
}

/// Guarantees the coordinator recording slot is released on every exit path.
///
/// The reservation is a long-lived resource held across separate FFI calls, so
/// a leak — from an early `?` return or a panic inside transcription/insertion —
/// leaves the app silently unable to record until relaunch. This guard releases
/// the slot in `Drop`. `disarm` commits the reservation when a session
/// legitimately stays reserved past the current scope (after a successful
/// `start_dictation_session`, where `finish`/`cancel` will release it later).
struct ReservationGuard {
    session_id: String,
    armed: bool,
}

impl ReservationGuard {
    fn new(session_id: String) -> Self {
        Self {
            session_id,
            armed: true,
        }
    }

    fn disarm(mut self) {
        self.armed = false;
    }
}

impl Drop for ReservationGuard {
    fn drop(&mut self) {
        if self.armed {
            abandon_coordinator_session(&self.session_id);
        }
    }
}

/// Frees a session from the coordinator, recovering the lock if a prior panic
/// poisoned it so the release path can never itself silently become a no-op.
fn abandon_coordinator_session(session_id: &str) {
    let mut coordinator = match COORDINATOR.lock() {
        Ok(coordinator) => coordinator,
        Err(poisoned) => poisoned.into_inner(),
    };
    coordinator.abandon(session_id);
}

fn monotonic_timestamp_ms() -> u64 {
    static ORIGIN: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    ORIGIN.get_or_init(Instant::now).elapsed().as_millis() as u64
}

/// The only language Swar recognises. Parakeet is an English engine and whisper
/// is held to the same language, so nothing downstream has to guess a script.
const ASR_LANGUAGE: &str = "english";

/// Whether a live preview has collapsed into a repetition loop.
///
/// The preview re-decodes the whole growing buffer roughly once a second with
/// greedy decoding, which is the classic way to make a decoder latch onto one
/// token and emit it forever ("आगे आगे आगे आगे…"). The preview is tentative
/// display only and never reaches the inserted text, so suppressing a degenerate
/// one costs a second of stale preview and saves the user a screenful of
/// garbage.
///
/// Deliberately strict about multi-word loops and lenient about single words:
/// "no no no" is something a person says, "the cat the cat the cat" is not.
fn is_degenerate_preview(value: &str) -> bool {
    let words = value.split_whitespace().collect::<Vec<_>>();
    if words.len() < 6 {
        return false;
    }
    for window in 1..=3usize {
        let threshold = if window == 1 { 4 } else { 3 };
        if longest_repeat_run(&words, window) >= threshold {
            return true;
        }
    }
    false
}

/// The longest run of one `window`-sized phrase repeated back to back.
fn longest_repeat_run(words: &[&str], window: usize) -> usize {
    if words.len() < window * 2 {
        return 0;
    }
    let mut longest = 0usize;
    let mut index = 0usize;
    while index + window * 2 <= words.len() {
        let phrase = &words[index..index + window];
        let mut run = 1usize;
        let mut next = index + window;
        while next + window <= words.len() && &words[next..next + window] == phrase {
            run += 1;
            next += window;
        }
        longest = longest.max(run);
        // A run of one still advances by a single word, so an offset loop is
        // found too.
        index += if run > 1 { run * window } else { 1 };
    }
    longest
}

fn transcript_contains_speech(value: &str) -> bool {
    let normalized = value
        .trim()
        .to_ascii_lowercase()
        .replace(['[', ']', '(', ')', '_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    !normalized.is_empty()
        && !matches!(
            normalized.as_str(),
            "blank audio" | "silence" | "no speech" | "music"
        )
}

fn select_input_device(host: &cpal::Host, requested_id: &str) -> Result<Device, String> {
    let devices = host
        .input_devices()
        .map_err(|error| error.to_string())?
        .collect::<Vec<_>>();

    if !requested_id.trim().is_empty() {
        if let Some(device) = devices.iter().find(|device| {
            device
                .id()
                .map(|id| id.to_string() == requested_id)
                .unwrap_or(false)
        }) {
            return Ok(device.clone());
        }
    }

    if let Some(device) = devices
        .iter()
        .find(|device| is_builtin_microphone_name(&device.to_string()))
    {
        return Ok(device.clone());
    }

    host.default_input_device()
        .or_else(|| devices.into_iter().next())
        .ok_or_else(|| "no microphone input device is available".to_owned())
}

fn is_builtin_microphone_name(name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    name.contains("built-in")
        || name.contains("internal microphone")
        || name.contains("microphone array")
        || (name.contains("macbook") && name.contains("microphone"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn speech_markers_filter_known_blank_tokens() {
        assert!(!transcript_contains_speech("[BLANK_AUDIO]"));
        assert!(transcript_contains_speech("hello"));
    }

    #[test]
    fn a_looping_preview_is_suppressed() {
        // The real failure: greedy decoding latched onto one Devanagari token.
        assert!(is_degenerate_preview("ये सब तो होगया और आगे आगे आगे आगे आगे आगे"));
        assert!(is_degenerate_preview(
            "so what we should do the cat the cat the cat the cat"
        ));
    }

    #[test]
    fn ordinary_speech_survives_the_repetition_guard() {
        assert!(!is_degenerate_preview("अरे और क्या बाकी है ये सब तो हो गया"));
        assert!(!is_degenerate_preview(
            "no no no that is not what I meant at all"
        ));
        // Emphatic repetition is speech, not a decoder loop.
        assert!(!is_degenerate_preview("बहुत बहुत धन्यवाद आपका दिन शुभ हो"));
    }

    #[test]
    fn a_short_preview_is_never_called_degenerate() {
        // Too little evidence to distinguish a loop from real emphasis.
        assert!(!is_degenerate_preview("हाँ हाँ हाँ हाँ"));
    }

    #[test]
    fn debug_output_redacts_the_provider_api_key() {
        let config = DictationSessionConfig {
            model_path: "model.bin".to_owned(),
            microphone_id: "mic".to_owned(),
            language: "english".to_owned(),
            writing_mode: "clean".to_owned(),
            source_application: "app".to_owned(),
            paste_automatically: true,
            restore_clipboard: false,
            maximum_seconds: 30,
            enable_live_preview: false,
            enhancement_provider: "byok".to_owned(),
            provider_endpoint: "https://example.test".to_owned(),
            provider_model: "gpt".to_owned(),
            provider_api_key: "super-secret-key".to_owned(),
            is_sensitive: false,
            cursor_text_before: String::new(),
            cursor_text_after: String::new(),
        };
        let rendered = format!("{config:?}");
        assert!(
            !rendered.contains("super-secret-key"),
            "the API key must never appear in Debug output"
        );
        assert!(rendered.contains("<redacted>"));
        assert!(rendered.contains("https://example.test"));
    }

    #[test]
    fn sensitive_dictation_is_never_written_to_history() {
        // Privacy P0: a password-field dictation must skip the history write so no
        // raw/clean/final text can reach SQLite. An ordinary dictation still is.
        assert!(!should_write_history(true), "sensitive must not persist");
        assert!(should_write_history(false), "ordinary must persist");
    }

    // Serialised in one test: the coordinator exposes a single global slot, so
    // splitting these into two `#[test]`s would let them race each other.
    #[test]
    fn reservation_guard_releases_on_drop_and_holds_when_disarmed() {
        fn reserve(session: &str) -> Result<(), String> {
            match COORDINATOR.lock() {
                Ok(mut coordinator) => coordinator.reserve_recording(session),
                Err(poisoned) => poisoned.into_inner().reserve_recording(session),
            }
        }

        // An armed guard frees the slot on drop, so the next session can start.
        reserve("guard-a").expect("reserve guard-a");
        drop(ReservationGuard::new("guard-a".to_owned()));
        reserve("guard-b").expect("slot must be free after the guard drops");
        abandon_coordinator_session("guard-b");

        // A disarmed guard keeps the reservation; a competing reserve must fail.
        reserve("guard-c").expect("reserve guard-c");
        ReservationGuard::new("guard-c".to_owned()).disarm();
        assert!(
            reserve("guard-d").is_err(),
            "a disarmed guard must leave the slot reserved"
        );
        abandon_coordinator_session("guard-c");
    }
}
