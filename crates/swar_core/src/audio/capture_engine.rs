use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

use cpal::{
    traits::{DeviceTrait, StreamTrait},
    Device, SampleFormat, Stream, StreamConfig,
};
use rtrb::{Consumer, Producer, RingBuffer};

const PRE_ROLL_MILLISECONDS: usize = 350;
const POST_ROLL_MILLISECONDS: u64 = 250;
const LEVEL_WINDOWS_PER_SECOND: u32 = 20;

type LevelCallback = Arc<dyn Fn(f64) + Send + Sync>;

static AUDIO_ENGINE: Mutex<Option<PersistentAudioEngine>> = Mutex::new(None);

pub(crate) struct CaptureStart {
    pub sample_rate: u32,
    pub dropped_samples_at_start: u64,
    pub stream_errors_at_start: u64,
}

struct ActiveBuffer {
    session_id: String,
    samples: Vec<f32>,
    maximum_samples: usize,
    level_callback: LevelCallback,
}

struct CaptureAccumulator {
    pre_roll: VecDeque<f32>,
    pre_roll_capacity: usize,
    active: Option<ActiveBuffer>,
    level_sum: f64,
    level_count: usize,
    level_window: usize,
}

impl CaptureAccumulator {
    fn new(sample_rate: u32) -> Self {
        Self {
            pre_roll: VecDeque::with_capacity(sample_rate as usize * PRE_ROLL_MILLISECONDS / 1_000),
            pre_roll_capacity: sample_rate as usize * PRE_ROLL_MILLISECONDS / 1_000,
            active: None,
            level_sum: 0.0,
            level_count: 0,
            level_window: (sample_rate / LEVEL_WINDOWS_PER_SECOND).max(1) as usize,
        }
    }

    fn begin(
        &mut self,
        session_id: String,
        maximum_samples: usize,
        level_callback: LevelCallback,
    ) -> Result<(), String> {
        if self.active.is_some() {
            return Err("another microphone capture is already active".to_owned());
        }
        let mut samples = self.pre_roll.iter().copied().collect::<Vec<_>>();
        samples.truncate(maximum_samples);
        self.active = Some(ActiveBuffer {
            session_id,
            samples,
            maximum_samples,
            level_callback,
        });
        self.level_sum = 0.0;
        self.level_count = 0;
        Ok(())
    }

    fn push(&mut self, sample: f32) -> Option<(LevelCallback, f64)> {
        if self.pre_roll_capacity > 0 {
            if self.pre_roll.len() == self.pre_roll_capacity {
                self.pre_roll.pop_front();
            }
            self.pre_roll.push_back(sample);
        }
        let active = self.active.as_mut()?;
        if active.samples.len() < active.maximum_samples {
            active.samples.push(sample);
        }
        self.level_sum += f64::from(sample * sample);
        self.level_count += 1;
        if self.level_count < self.level_window {
            return None;
        }
        let rms = (self.level_sum / self.level_count as f64)
            .sqrt()
            .clamp(0.0, 1.0);
        self.level_sum = 0.0;
        self.level_count = 0;
        Some((active.level_callback.clone(), rms))
    }

    fn finish(&mut self, session_id: &str) -> Result<Vec<f32>, String> {
        let active = self
            .active
            .take()
            .ok_or_else(|| "no microphone capture is active".to_owned())?;
        if active.session_id != session_id {
            self.active = Some(active);
            return Err("the requested microphone capture is not active".to_owned());
        }
        Ok(active.samples)
    }

    fn cancel(&mut self, session_id: &str) -> Result<(), String> {
        self.finish(session_id).map(|_| ())
    }

    fn snapshot(&self, session_id: &str) -> Result<Vec<f32>, String> {
        let active = self
            .active
            .as_ref()
            .ok_or_else(|| "no microphone capture is active".to_owned())?;
        if active.session_id != session_id {
            return Err("the requested microphone capture is not active".to_owned());
        }
        Ok(active.samples.clone())
    }
}

struct PersistentAudioEngine {
    device_id: String,
    sample_rate: u32,
    accumulator: Arc<Mutex<CaptureAccumulator>>,
    dropped_samples: Arc<AtomicU64>,
    stream_errors: Arc<AtomicU64>,
    running: Arc<AtomicBool>,
    stream: Option<Stream>,
    worker: Option<thread::JoinHandle<()>>,
}

impl PersistentAudioEngine {
    fn start(device: &Device, device_id: String) -> Result<Self, String> {
        let supported = device
            .default_input_config()
            .map_err(|error| error.to_string())?;
        let format = supported.sample_format();
        let config: StreamConfig = supported.into();
        let sample_rate = config.sample_rate;
        let channels = usize::from(config.channels);
        let ring_capacity = sample_rate as usize * 10;
        let (producer, consumer) = RingBuffer::<f32>::new(ring_capacity);
        let accumulator = Arc::new(Mutex::new(CaptureAccumulator::new(sample_rate)));
        let dropped_samples = Arc::new(AtomicU64::new(0));
        let stream_errors = Arc::new(AtomicU64::new(0));
        let running = Arc::new(AtomicBool::new(true));
        let worker = spawn_worker(consumer, accumulator.clone(), running.clone())?;
        let stream = build_input_stream(
            device,
            &config,
            format,
            channels,
            producer,
            dropped_samples.clone(),
            stream_errors.clone(),
        )?;
        stream.play().map_err(|error| error.to_string())?;
        Ok(Self {
            device_id,
            sample_rate,
            accumulator,
            dropped_samples,
            stream_errors,
            running,
            stream: Some(stream),
            worker: Some(worker),
        })
    }

    fn begin(
        &self,
        session_id: String,
        maximum_seconds: u32,
        level_callback: LevelCallback,
    ) -> Result<CaptureStart, String> {
        self.accumulator
            .lock()
            .map_err(|_| "audio accumulator lock poisoned".to_owned())?
            .begin(
                session_id,
                self.sample_rate as usize * maximum_seconds.clamp(5, 300) as usize,
                level_callback,
            )?;
        Ok(CaptureStart {
            sample_rate: self.sample_rate,
            dropped_samples_at_start: self.dropped_samples.load(Ordering::Acquire),
            stream_errors_at_start: self.stream_errors.load(Ordering::Acquire),
        })
    }
}

impl Drop for PersistentAudioEngine {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Release);
        drop(self.stream.take());
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

pub(crate) fn begin_capture(
    device: &Device,
    device_id: String,
    session_id: String,
    maximum_seconds: u32,
    level_callback: LevelCallback,
) -> Result<CaptureStart, String> {
    let mut engine = AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())?;
    if engine
        .as_ref()
        .is_none_or(|current| current.device_id != device_id)
    {
        *engine = Some(PersistentAudioEngine::start(device, device_id)?);
    }
    engine
        .as_ref()
        .ok_or_else(|| "audio engine did not start".to_owned())?
        .begin(session_id, maximum_seconds, level_callback)
}

/// Starts the persistent native stream before the first shortcut activation so
/// the first dictation receives the same pre-roll as every later dictation.
pub(crate) fn prepare(device: &Device, device_id: String) -> Result<u32, String> {
    let mut engine = AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())?;
    if engine
        .as_ref()
        .is_none_or(|current| current.device_id != device_id)
    {
        *engine = Some(PersistentAudioEngine::start(device, device_id)?);
    }
    engine
        .as_ref()
        .map(|value| value.sample_rate)
        .ok_or_else(|| "audio engine did not start".to_owned())
}

pub(crate) fn finish_capture(
    session_id: &str,
    dropped_samples_at_start: u64,
    stream_errors_at_start: u64,
) -> Result<Vec<f32>, String> {
    // Key-up marks the end of intent, not necessarily the end of the final
    // phoneme. Keep a short post-roll while capture remains Rust-owned.
    thread::sleep(Duration::from_millis(POST_ROLL_MILLISECONDS));
    let engine = AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())?;
    let engine = engine
        .as_ref()
        .ok_or_else(|| "audio engine is unavailable".to_owned())?;
    if engine.dropped_samples.load(Ordering::Acquire) > dropped_samples_at_start {
        return Err("audio buffer overflowed; shorten the dictation and try again".to_owned());
    }
    if engine.stream_errors.load(Ordering::Acquire) > stream_errors_at_start {
        return Err("the microphone stream reported an input error".to_owned());
    }
    let result = engine
        .accumulator
        .lock()
        .map_err(|_| "audio accumulator lock poisoned".to_owned())?
        .finish(session_id);
    result
}

pub(crate) fn cancel_capture(session_id: &str) -> Result<(), String> {
    let engine = AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())?;
    let result = engine
        .as_ref()
        .ok_or_else(|| "audio engine is unavailable".to_owned())?
        .accumulator
        .lock()
        .map_err(|_| "audio accumulator lock poisoned".to_owned())?
        .cancel(session_id);
    result
}

pub(crate) fn snapshot(session_id: &str) -> Result<(Vec<f32>, u32), String> {
    let engine = AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())?;
    let engine = engine
        .as_ref()
        .ok_or_else(|| "audio engine is unavailable".to_owned())?;
    let samples = engine
        .accumulator
        .lock()
        .map_err(|_| "audio accumulator lock poisoned".to_owned())?
        .snapshot(session_id)?;
    Ok((samples, engine.sample_rate))
}

pub(crate) fn release() -> Result<(), String> {
    *AUDIO_ENGINE
        .lock()
        .map_err(|_| "audio engine lock poisoned".to_owned())? = None;
    Ok(())
}

fn spawn_worker(
    mut consumer: Consumer<f32>,
    accumulator: Arc<Mutex<CaptureAccumulator>>,
    running: Arc<AtomicBool>,
) -> Result<thread::JoinHandle<()>, String> {
    thread::Builder::new()
        .name("swar-audio-worker".to_owned())
        .spawn(move || loop {
            let mut drained = false;
            while let Ok(sample) = consumer.pop() {
                drained = true;
                let level = accumulator
                    .lock()
                    .ok()
                    .and_then(|mut value| value.push(sample));
                if let Some((callback, rms)) = level {
                    callback(rms);
                }
            }
            if !running.load(Ordering::Acquire) && !drained {
                break;
            }
            if !drained {
                thread::sleep(Duration::from_millis(4));
            }
        })
        .map_err(|error| error.to_string())
}

fn build_input_stream(
    device: &Device,
    config: &StreamConfig,
    format: SampleFormat,
    channels: usize,
    producer: Producer<f32>,
    dropped: Arc<AtomicU64>,
    stream_errors: Arc<AtomicU64>,
) -> Result<Stream, String> {
    match format {
        SampleFormat::F32 => build_typed_stream(
            device,
            config,
            channels,
            producer,
            dropped,
            stream_errors,
            |x: f32| x,
        ),
        SampleFormat::I16 => build_typed_stream(
            device,
            config,
            channels,
            producer,
            dropped,
            stream_errors,
            |x: i16| f32::from(x) / 32_768.0,
        ),
        SampleFormat::U16 => build_typed_stream(
            device,
            config,
            channels,
            producer,
            dropped,
            stream_errors,
            |x: u16| (f32::from(x) - 32_768.0) / 32_768.0,
        ),
        _ => Err(format!("unsupported microphone sample format: {format:?}")),
    }
}

fn build_typed_stream<T, F>(
    device: &Device,
    config: &StreamConfig,
    channels: usize,
    mut producer: Producer<f32>,
    dropped: Arc<AtomicU64>,
    stream_errors: Arc<AtomicU64>,
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
            move |_error| {
                stream_errors.fetch_add(1, Ordering::Relaxed);
            },
            None,
        )
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pre_roll_keeps_only_the_latest_samples() {
        let mut accumulator = CaptureAccumulator::new(1_000);
        for sample in 0..500 {
            accumulator.push(sample as f32);
        }
        accumulator
            .begin("session".to_owned(), 1_000, Arc::new(|_| {}))
            .expect("capture starts");
        let samples = accumulator.finish("session").expect("capture finishes");
        assert_eq!(samples.len(), 350);
        assert_eq!(samples[0], 150.0);
        assert_eq!(samples[349], 499.0);
    }

    #[test]
    fn active_capture_is_bounded() {
        let mut accumulator = CaptureAccumulator::new(100);
        accumulator
            .begin("session".to_owned(), 5, Arc::new(|_| {}))
            .expect("capture starts");
        for sample in 0..20 {
            accumulator.push(sample as f32);
        }
        let samples = accumulator.finish("session").expect("capture finishes");
        assert_eq!(samples.len(), 5);
    }
}
