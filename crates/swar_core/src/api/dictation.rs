use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, LazyLock, Mutex,
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use crate::{
    api::personalization,
    asr::model_registry,
    audio::capture_engine,
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
use flutter_rust_bridge::frb;
use uuid::Uuid;

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

#[derive(Clone, Debug)]
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
    preview_running: Arc<AtomicBool>,
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
            release_recording_reservation(&session_id);
            return Err(error);
        }
    };
    let device_id = device
        .id()
        .map(|id| id.to_string())
        .unwrap_or_else(|_| device.to_string());
    let level_sink = sink.clone();
    let level_session_id = session_id.clone();
    let capture_start = match capture_engine::begin_capture(
        &device,
        device_id,
        session_id.clone(),
        config.maximum_seconds,
        Arc::new(move |rms| {
            let _ = level_sink.add(DictationEvent {
                session_id: level_session_id.clone(),
                kind: DictationEventKind::AudioLevel,
                audio_level: Some(rms),
                message: None,
                timestamp_ms: monotonic_timestamp_ms(),
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
            release_recording_reservation(&session_id);
            return Err(error);
        }
    };
    let recording = lifecycle
        .transition(DictationState::Recording, "microphone ready")
        .map_err(|error| error.to_string())?;
    emit_transition(&sink, &session_id, recording, None);
    let preview_running = Arc::new(AtomicBool::new(config.enable_live_preview));
    let preview_worker = config.enable_live_preview.then(|| {
        spawn_preview_worker(
            session_id.clone(),
            config.model_path.clone(),
            config.language.clone(),
            sink.clone(),
            preview_running.clone(),
        )
    });

    *active = Some(ActiveCapture {
        id: session_id.clone(),
        config,
        sample_rate: capture_start.sample_rate,
        started_at: Instant::now(),
        dropped_samples_at_start: capture_start.dropped_samples_at_start,
        preview_running,
        preview_worker,
        sink,
        lifecycle,
    });
    Ok(session_id)
}

/// Stops capture, transcribes locally with whisper.cpp, cleans, inserts, and persists.
pub fn finish_dictation_session(session_id: String) -> Result<DictationCompletion, String> {
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
            complete_coordinator_session(&session_id);
            Ok(completion)
        }
        Err(error) => {
            let _ = transition_capture(&mut capture, DictationState::Failed, error.clone());
            complete_coordinator_session(&session_id);
            Err(error)
        }
    }
}

fn finish_capture(capture: &mut ActiveCapture) -> Result<DictationCompletion, String> {
    stop_preview(capture);
    let captured = capture_engine::finish_capture(&capture.id, capture.dropped_samples_at_start)?;
    if captured.is_empty() {
        return Err("no microphone audio was captured".to_owned());
    }

    let processing_started = Instant::now();
    let mono_16khz = resample_linear(&captured, capture.sample_rate, 16_000);
    transition_capture(
        capture,
        DictationState::Transcribing,
        "audio drained and resampled",
    )?;
    let raw_text = model_registry::transcribe(
        &capture.config.model_path,
        &capture.config.language,
        &mono_16khz,
    )?;
    if !transcript_contains_speech(&raw_text) {
        return Err("speech was not detected".to_owned());
    }
    transition_capture(capture, DictationState::Cleaning, "final transcript ready")?;
    let personalized_raw = personalization::apply_vocabulary(&raw_text);
    let clean_text =
        text_cleanup::clean_transcript(&personalized_raw, &capture.config.writing_mode);
    if clean_text.trim().is_empty() {
        return Err("speech was not detected".to_owned());
    }
    let enhancement = enhancement::enhance_transcript(
        &personalized_raw,
        &clean_text,
        &capture.config.writing_mode,
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
    transition_capture(capture, DictationState::Inserting, "cleanup completed")?;
    let insertion = insertion::insert_with_clipboard(
        &capture.id,
        &final_text,
        capture.config.paste_automatically,
        capture.config.restore_clipboard,
    )?;
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
        .map_err(|error| error.to_string())?
        .as_millis() as i64;

    storage::save_dictation(NewDictation {
        id: &capture.id,
        created_at_ms,
        raw_text: &raw_text,
        cleaned_text: &final_text,
        final_text: &final_text,
        language: &capture.config.language,
        writing_mode: &capture.config.writing_mode,
        source_application: &capture.config.source_application,
        audio_duration_ms,
        speech_duration_ms: audio_duration_ms,
        processing_duration_ms,
        asr_engine: "whisper.cpp",
        asr_model_id: Path::new(&capture.config.model_path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("whisper-model"),
        insertion_status: insertion.status,
        insertion_method: insertion.method,
    })?;

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

/// Cancels the active capture and discards all PCM without writing history.
pub fn cancel_dictation_session(session_id: String) -> Result<(), String> {
    let mut capture = take_capture(&session_id)?;
    transition_capture(&mut capture, DictationState::Cancelled, "user cancelled")?;
    stop_preview(&mut capture);
    capture_engine::cancel_capture(&session_id)?;
    COORDINATOR
        .lock()
        .map_err(|_| "dictation coordinator lock poisoned".to_owned())?
        .cancel_recording(&session_id)?;
    transition_capture(&mut capture, DictationState::Idle, "session released")?;
    Ok(())
}

#[frb(sync)]
pub fn offline_model_is_ready(model_path: String) -> bool {
    !model_path.trim().is_empty() && Path::new(&model_path).is_file()
}

/// Loads the selected model on the dedicated ASR worker before the first dictation.
pub fn prepare_dictation_engine(model_path: String) -> Result<bool, String> {
    model_registry::prepare(&model_path).map(|status| status.already_loaded)
}

/// Releases the warm model without stopping the dedicated ASR worker.
pub fn release_dictation_engine() -> Result<(), String> {
    model_registry::unload()?;
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
) -> thread::JoinHandle<()> {
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
                let mono_16khz = resample_linear(&samples, sample_rate, 16_000);
                let Ok(partial) =
                    model_registry::transcribe_preview(&model_path, &language, &mono_16khz)
                else {
                    continue;
                };
                if partial.is_empty()
                    || partial == previous
                    || !transcript_contains_speech(&partial)
                {
                    continue;
                }
                previous.clone_from(&partial);
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
        })
        .expect("the optional preview worker must start")
}

fn stop_preview(capture: &mut ActiveCapture) {
    capture.preview_running.store(false, Ordering::Release);
    if let Some(worker) = capture.preview_worker.take() {
        let _ = worker.join();
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

fn release_recording_reservation(session_id: &str) {
    if let Ok(mut coordinator) = COORDINATOR.lock() {
        let _ = coordinator.cancel_recording(session_id);
    }
}

fn complete_coordinator_session(session_id: &str) {
    if let Ok(mut coordinator) = COORDINATOR.lock() {
        let _ = coordinator.complete(session_id);
    }
}

fn monotonic_timestamp_ms() -> u64 {
    static ORIGIN: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    ORIGIN.get_or_init(Instant::now).elapsed().as_millis() as u64
}

fn resample_linear(input: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if input.is_empty() || source_rate == 0 || target_rate == 0 {
        return Vec::new();
    }
    if source_rate == target_rate {
        return input.to_vec();
    }
    let output_len = input.len() * target_rate as usize / source_rate as usize;
    let ratio = source_rate as f64 / target_rate as f64;
    (0..output_len)
        .map(|index| {
            let position = index as f64 * ratio;
            let lower = position.floor() as usize;
            let upper = (lower + 1).min(input.len() - 1);
            let fraction = (position - lower as f64) as f32;
            input[lower] * (1.0 - fraction) + input[upper] * fraction
        })
        .collect()
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
    fn resamples_to_the_asr_boundary_rate() {
        let input = vec![0.5_f32; 48_000];
        let output = resample_linear(&input, 48_000, 16_000);
        assert_eq!(output.len(), 16_000);
        assert!(output
            .iter()
            .all(|sample| (*sample - 0.5).abs() < f32::EPSILON));
    }
}
