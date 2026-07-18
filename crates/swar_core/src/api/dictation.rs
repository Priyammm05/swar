use std::{
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use cpal::{
    Device, SampleFormat, Stream, StreamConfig,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};
use flutter_rust_bridge::frb;
use rtrb::{Consumer, Producer, RingBuffer};
use uuid::Uuid;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use crate::{
    frb_generated::StreamSink,
    insertion,
    storage::{self, NewDictation},
    text_cleanup,
};

static ACTIVE_CAPTURE: Mutex<Option<ActiveCapture>> = Mutex::new(None);

#[derive(Clone, Debug)]
pub enum DictationEventKind {
    Preparing,
    Recording,
    AudioLevel,
    Finalising,
    Cancelled,
    Failed,
}

#[derive(Clone, Debug)]
pub struct DictationEvent {
    pub session_id: String,
    pub kind: DictationEventKind,
    pub audio_level: Option<f64>,
    pub message: Option<String>,
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
    running: Arc<AtomicBool>,
    dropped_samples: Arc<AtomicU64>,
    stream: Stream,
    worker: thread::JoinHandle<Vec<f32>>,
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

    let session_id = Uuid::new_v4().to_string();
    let _ = sink.add(DictationEvent {
        session_id: session_id.clone(),
        kind: DictationEventKind::Preparing,
        audio_level: None,
        message: None,
    });

    let host = cpal::default_host();
    let device = select_input_device(&host, &config.microphone_id)?;
    let supported = device
        .default_input_config()
        .map_err(|error| error.to_string())?;
    let sample_format = supported.sample_format();
    let stream_config: StreamConfig = supported.into();
    let sample_rate = stream_config.sample_rate;
    let channels = usize::from(stream_config.channels);
    let capacity = sample_rate as usize * config.maximum_seconds.clamp(5, 300) as usize;
    let (producer, consumer) = RingBuffer::<f32>::new(capacity);
    let running = Arc::new(AtomicBool::new(true));
    let dropped_samples = Arc::new(AtomicU64::new(0));
    let worker = spawn_audio_worker(
        consumer,
        running.clone(),
        sample_rate,
        sink,
        session_id.clone(),
    );
    let stream = build_input_stream(
        &device,
        &stream_config,
        sample_format,
        channels,
        producer,
        dropped_samples.clone(),
    )?;
    stream.play().map_err(|error| error.to_string())?;

    *active = Some(ActiveCapture {
        id: session_id.clone(),
        config,
        sample_rate,
        started_at: Instant::now(),
        running,
        dropped_samples,
        stream,
        worker,
    });
    Ok(session_id)
}

/// Stops capture, transcribes locally with whisper.cpp, cleans, inserts, and persists.
pub fn finish_dictation_session(session_id: String) -> Result<DictationCompletion, String> {
    let capture = take_capture(&session_id)?;
    capture.running.store(false, Ordering::Release);
    drop(capture.stream);
    let captured = capture
        .worker
        .join()
        .map_err(|_| "audio worker stopped unexpectedly".to_owned())?;
    if capture.dropped_samples.load(Ordering::Relaxed) > 0 {
        return Err("audio buffer overflowed; shorten the dictation and try again".to_owned());
    }
    if captured.is_empty() {
        return Err("no microphone audio was captured".to_owned());
    }

    let processing_started = Instant::now();
    let mono_16khz = resample_linear(&captured, capture.sample_rate, 16_000);
    let raw_text = transcribe(
        &capture.config.model_path,
        &capture.config.language,
        &mono_16khz,
    )?;
    if !transcript_contains_speech(&raw_text) {
        return Err("speech was not detected".to_owned());
    }
    let final_text = text_cleanup::clean_transcript(&raw_text, &capture.config.writing_mode);
    if final_text.trim().is_empty() {
        return Err("speech was not detected".to_owned());
    }
    let insertion = insertion::insert_with_clipboard(
        &final_text,
        capture.config.paste_automatically,
        capture.config.restore_clipboard,
    )?;
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
        session_id,
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
    let capture = take_capture(&session_id)?;
    capture.running.store(false, Ordering::Release);
    drop(capture.stream);
    let _ = capture.worker.join();
    Ok(())
}

#[frb(sync)]
pub fn offline_model_is_ready(model_path: String) -> bool {
    !model_path.trim().is_empty() && Path::new(&model_path).is_file()
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

fn spawn_audio_worker(
    mut consumer: Consumer<f32>,
    running: Arc<AtomicBool>,
    sample_rate: u32,
    sink: StreamSink<DictationEvent>,
    session_id: String,
) -> thread::JoinHandle<Vec<f32>> {
    thread::spawn(move || {
        let _ = sink.add(DictationEvent {
            session_id: session_id.clone(),
            kind: DictationEventKind::Recording,
            audio_level: None,
            message: None,
        });
        let mut samples = Vec::new();
        let level_window = (sample_rate / 20).max(1) as usize;
        let mut level_sum = 0.0_f64;
        let mut level_count = 0_usize;
        loop {
            let mut drained = false;
            while let Ok(sample) = consumer.pop() {
                drained = true;
                samples.push(sample);
                level_sum += f64::from(sample * sample);
                level_count += 1;
                if level_count >= level_window {
                    let rms = (level_sum / level_count as f64).sqrt().clamp(0.0, 1.0);
                    let _ = sink.add(DictationEvent {
                        session_id: session_id.clone(),
                        kind: DictationEventKind::AudioLevel,
                        audio_level: Some(rms),
                        message: None,
                    });
                    level_sum = 0.0;
                    level_count = 0;
                }
            }
            if !running.load(Ordering::Acquire) && !drained {
                break;
            }
            if !drained {
                thread::sleep(Duration::from_millis(4));
            }
        }
        let _ = sink.add(DictationEvent {
            session_id,
            kind: DictationEventKind::Finalising,
            audio_level: None,
            message: None,
        });
        samples
    })
}

fn build_input_stream(
    device: &Device,
    config: &StreamConfig,
    format: SampleFormat,
    channels: usize,
    producer: Producer<f32>,
    dropped: Arc<AtomicU64>,
) -> Result<Stream, String> {
    match format {
        SampleFormat::F32 => {
            build_typed_stream(device, config, channels, producer, dropped, |x: f32| x)
        }
        SampleFormat::I16 => {
            build_typed_stream(device, config, channels, producer, dropped, |x: i16| {
                f32::from(x) / 32_768.0
            })
        }
        SampleFormat::U16 => {
            build_typed_stream(device, config, channels, producer, dropped, |x: u16| {
                (f32::from(x) - 32_768.0) / 32_768.0
            })
        }
        _ => Err(format!("unsupported microphone sample format: {format:?}")),
    }
}

fn build_typed_stream<T, F>(
    device: &Device,
    config: &StreamConfig,
    channels: usize,
    mut producer: Producer<f32>,
    dropped: Arc<AtomicU64>,
    convert: F,
) -> Result<Stream, String>
where
    T: cpal::SizedSample + Copy,
    F: Fn(T) -> f32 + Send + 'static + Copy,
{
    device
        .build_input_stream(
            *config,
            move |data: &[T], _| {
                for frame in data.chunks(channels) {
                    let mono = frame.iter().copied().map(convert).sum::<f32>() / frame.len() as f32;
                    if producer.push(mono).is_err() {
                        dropped.fetch_add(1, Ordering::Relaxed);
                    }
                }
            },
            move |_error| {},
            None,
        )
        .map_err(|error| error.to_string())
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

fn transcribe(model_path: &str, language: &str, samples: &[f32]) -> Result<String, String> {
    let context = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
        .map_err(|error| format!("could not load offline model: {error}"))?;
    let mut state = context.create_state().map_err(|error| error.to_string())?;
    // Beam search materially improves short-form dictation accuracy over the
    // previous single greedy candidate without injecting vocabulary or
    // rewriting recognized words after transcription.
    let mut params = FullParams::new(SamplingStrategy::BeamSearch {
        beam_size: 5,
        patience: -1.0,
    });
    params.set_translate(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    // Dictation only needs text. Disabling timestamp tokens prevents short
    // push-to-talk captures from entering whisper.cpp's timestamp-only discard
    // branch after it has already recognized valid words.
    params.set_no_timestamps(true);
    params.set_single_segment(true);
    params.set_n_threads(available_threads());
    match language.to_ascii_lowercase().as_str() {
        "english" => params.set_language(Some("en")),
        "hindi" => params.set_language(Some("hi")),
        _ => params.set_language(None),
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

fn available_threads() -> i32 {
    thread::available_parallelism()
        .map(|count| count.get().saturating_sub(1).clamp(1, 8) as i32)
        .unwrap_or(2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resamples_to_the_asr_boundary_rate() {
        let input = vec![0.5_f32; 48_000];
        let output = resample_linear(&input, 48_000, 16_000);
        assert_eq!(output.len(), 16_000);
        assert!(
            output
                .iter()
                .all(|sample| (*sample - 0.5).abs() < f32::EPSILON)
        );
    }
}
