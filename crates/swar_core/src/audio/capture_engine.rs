use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use cpal::{
    traits::{DeviceTrait, StreamTrait},
    Device, SampleFormat, Stream, StreamConfig,
};
use rtrb::{Consumer, Producer, RingBuffer};

const PRE_ROLL_MILLISECONDS: usize = 350;
const POST_ROLL_MILLISECONDS: u64 = 250;
const LEVEL_WINDOWS_PER_SECOND: u32 = 20;
/// How long teardown waits for the audio worker to exit before detaching it, so
/// a blocked level callback can never hang `Drop` (and the global audio lock).
const WORKER_JOIN_TIMEOUT: Duration = Duration::from_secs(2);
/// How long `finish_capture` waits for the worker to drain the ring buffer, so
/// the final tail is not left stranded in the worker's in-flight batch when the
/// active buffer is taken.
const DRAIN_BARRIER_TIMEOUT: Duration = Duration::from_millis(50);

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

impl Drop for ActiveBuffer {
    fn drop(&mut self) {
        // Dropping a Vec only frees memory; it does not scrub dictation audio
        // from the heap. Overwrite the captured PCM first (privacy guarantee).
        self.samples.iter_mut().for_each(|sample| *sample = 0.0);
    }
}

impl Drop for CaptureAccumulator {
    fn drop(&mut self) {
        // Scrub the rolling pre-roll — a few hundred ms of continuously captured
        // microphone audio — when the engine is torn down. The active buffer, if
        // any, scrubs itself through ActiveBuffer::drop.
        self.pre_roll.iter_mut().for_each(|sample| *sample = 0.0);
    }
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
        let mut active = self
            .active
            .take()
            .ok_or_else(|| "no microphone capture is active".to_owned())?;
        if active.session_id != session_id {
            self.active = Some(active);
            return Err("the requested microphone capture is not active".to_owned());
        }
        // Move the samples out so the caller owns them; the now-empty ActiveBuffer
        // scrubs nothing on drop, and the caller scrubs the buffer after use.
        Ok(std::mem::take(&mut active.samples))
    }

    fn cancel(&mut self, session_id: &str) -> Result<(), String> {
        self.finish(session_id).map(|_| ())
    }

    /// Samples recorded after `offset`, so a caller that has already consumed the
    /// earlier part of the utterance does not copy or re-read it.
    fn snapshot_from(&self, session_id: &str, offset: usize) -> Result<Vec<f32>, String> {
        let active = self
            .active
            .as_ref()
            .ok_or_else(|| "no microphone capture is active".to_owned())?;
        if active.session_id != session_id {
            return Err("the requested microphone capture is not active".to_owned());
        }
        Ok(active.samples.get(offset..).unwrap_or(&[]).to_vec())
    }
}

struct PersistentAudioEngine {
    device_id: String,
    sample_rate: u32,
    accumulator: Arc<Mutex<CaptureAccumulator>>,
    dropped_samples: Arc<AtomicU64>,
    stream_errors: Arc<AtomicU64>,
    running: Arc<AtomicBool>,
    worker_exited: Arc<AtomicBool>,
    worker_idle: Arc<AtomicBool>,
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
        let worker_exited = Arc::new(AtomicBool::new(false));
        let worker_idle = Arc::new(AtomicBool::new(true));
        let worker = spawn_worker(
            consumer,
            accumulator.clone(),
            running.clone(),
            worker_exited.clone(),
            worker_idle.clone(),
        )?;
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
            worker_exited,
            worker_idle,
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
        // Dropping the stream disconnects the ring buffer, so the worker's next
        // `pop` fails and it exits promptly — unless it is stuck inside a level
        // callback. Wait a bounded time for a clean exit, then detach rather
        // than block `Drop` (which runs under the global audio lock) forever.
        drop(self.stream.take());
        if let Some(worker) = self.worker.take() {
            let deadline = Instant::now() + WORKER_JOIN_TIMEOUT;
            while !self.worker_exited.load(Ordering::Acquire) && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(5));
            }
            if self.worker_exited.load(Ordering::Acquire) {
                let _ = worker.join();
            }
            // Otherwise leave the handle to detach; joining could hang forever.
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
    // Tolerate a brief glitch (~100 ms of dropped samples) rather than discard
    // an entire utterance over a single dropped sample; only a sustained
    // overflow (worker starved for long enough to lose ~100 ms) fails.
    let overrun_tolerance = u64::from(engine.sample_rate) / 10;
    if engine.dropped_samples.load(Ordering::Acquire) > dropped_samples_at_start + overrun_tolerance
    {
        return Err("audio buffer overflowed; shorten the dictation and try again".to_owned());
    }
    if engine.stream_errors.load(Ordering::Acquire) > stream_errors_at_start {
        return Err("the microphone stream reported an input error".to_owned());
    }
    // Drain barrier: wait for the worker to report the ring empty (everything
    // popped is now in the accumulator) before taking the buffer, so a tail
    // sitting in the worker's in-flight batch is not truncated. Bounded so a
    // continuously busy worker can never block completion.
    let drain_deadline = Instant::now() + DRAIN_BARRIER_TIMEOUT;
    while !engine.worker_idle.load(Ordering::Acquire) && Instant::now() < drain_deadline {
        thread::sleep(Duration::from_millis(2));
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

/// Audio recorded after `offset`, with the capture sample rate.
///
/// The streaming decoder uses this to read only what it has not already
/// transcribed. Reading the whole buffer each time made every pass redo all the
/// work of the previous one, and none of it was reused for the final transcript.
pub(crate) fn snapshot_from(session_id: &str, offset: usize) -> Result<(Vec<f32>, u32), String> {
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
        .snapshot_from(session_id, offset)?;
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
    exited: Arc<AtomicBool>,
    idle: Arc<AtomicBool>,
) -> Result<thread::JoinHandle<()>, String> {
    thread::Builder::new()
        .name("swar-audio-worker".to_owned())
        .spawn(move || {
            // Reused across passes so the worker does not allocate in its hot loop.
            let mut batch: Vec<f32> = Vec::new();
            let mut levels: Vec<(LevelCallback, f64)> = Vec::new();
            loop {
                batch.clear();
                while let Ok(sample) = consumer.pop() {
                    batch.push(sample);
                }
                let drained = !batch.is_empty();
                if drained {
                    // Not idle: samples popped but not yet in the accumulator.
                    idle.store(false, Ordering::Release);
                    // Take the accumulator lock once per drain pass instead of
                    // once per sample (~16k locks/sec while capturing).
                    if let Ok(mut accumulator) = accumulator.lock() {
                        for sample in batch.drain(..) {
                            if let Some(level) = accumulator.push(sample) {
                                levels.push(level);
                            }
                        }
                    }
                    // Run level callbacks after releasing the lock.
                    for (callback, rms) in levels.drain(..) {
                        callback(rms);
                    }
                }
                if !running.load(Ordering::Acquire) && !drained {
                    break;
                }
                if !drained {
                    // The ring is empty and everything popped is now in the
                    // accumulator, so a reader can safely take the buffer.
                    idle.store(true, Ordering::Release);
                    thread::sleep(Duration::from_millis(4));
                }
            }
            exited.store(true, Ordering::Release);
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
