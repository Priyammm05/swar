use std::{fs, path::Path, time::Instant};

use flutter_rust_bridge::frb;
use serde::Serialize;

use crate::{asr::model_registry, audio::speech, enhancement, text_cleanup};

#[derive(Clone, Debug, Serialize)]
pub struct TextPipelineBenchmarkReport {
    pub iterations: u32,
    pub samples: u64,
    pub p50_microseconds: u64,
    pub p95_microseconds: u64,
    pub maximum_microseconds: u64,
    pub operations_per_second: f64,
}

#[derive(Clone, Debug, Serialize)]
pub struct AsrFileBenchmarkReport {
    pub language: String,
    pub expected_text: String,
    pub actual_text: String,
    pub word_error_rate: f64,
    pub processing_milliseconds: u64,
    pub audio_milliseconds: u64,
    pub realtime_factor: f64,
}

/// Runs the real, installed whisper.cpp model against a 16-bit mono WAV file.
/// This is development and release-gate tooling; it never stores microphone
/// audio and is deliberately not exposed across the Flutter bridge.
#[frb(ignore)]
pub fn run_asr_file_benchmark(
    model_path: &str,
    wav_path: &str,
    language: &str,
    expected_text: &str,
) -> Result<AsrFileBenchmarkReport, String> {
    let (sample_rate, samples) = read_pcm16_mono_wav(Path::new(wav_path))?;
    if sample_rate != 16_000 {
        return Err("benchmark WAV must be mono 16 kHz PCM16".to_owned());
    }
    let audio_milliseconds = samples.len() as u64 * 1_000 / sample_rate as u64;
    let speech = speech::retain_probable_speech(&samples, sample_rate);
    if speech.samples.is_empty() {
        return Err("benchmark fixture did not contain probable speech".to_owned());
    }
    let started = Instant::now();
    // No vocabulary bias in the benchmark: results must stay reproducible and
    // independent of whatever a user happens to have saved.
    let decoded = model_registry::transcribe(model_path, language, &speech.samples, "")?;
    // Score the text the user actually receives. Hinglish and Automatic
    // transliterate Devanagari spans to Roman before insertion, so measuring the
    // raw decode marked a correct Hinglish transcript wrong purely for being in
    // the other script, and understated every model on that route.
    let actual_text = crate::language::to_output_script(&decoded, language);
    let processing_milliseconds = started.elapsed().as_millis() as u64;
    Ok(AsrFileBenchmarkReport {
        language: language.to_owned(),
        expected_text: expected_text.to_owned(),
        word_error_rate: word_error_rate(expected_text, &actual_text),
        actual_text,
        processing_milliseconds,
        audio_milliseconds,
        realtime_factor: processing_milliseconds as f64 / audio_milliseconds.max(1) as f64,
    })
}

/// Runs the primary engine (the fast ONNX helper) against a 16-bit mono WAV.
///
/// The whisper entry point above cannot reach it, so before this existed the
/// corpus could only be scored on the fallback engine — which is not what a user
/// actually gets. Development and release-gate tooling only; never exposed across
/// the Flutter bridge and it never stores microphone audio.
#[frb(ignore)]
pub fn run_fast_asr_file_benchmark(
    wav_path: &str,
    expected_text: &str,
) -> Result<AsrFileBenchmarkReport, String> {
    let (sample_rate, samples) = read_pcm16_mono_wav(Path::new(wav_path))?;
    if sample_rate != 16_000 {
        return Err("benchmark WAV must be mono 16 kHz PCM16".to_owned());
    }
    let audio_milliseconds = samples.len() as u64 * 1_000 / sample_rate as u64;
    let speech = speech::retain_probable_speech(&samples, sample_rate);
    if speech.samples.is_empty() {
        return Err("benchmark fixture did not contain probable speech".to_owned());
    }
    let started = Instant::now();
    let actual_text = crate::asr_client::transcribe(&speech.samples, "english")?;
    let processing_milliseconds = started.elapsed().as_millis() as u64;
    Ok(AsrFileBenchmarkReport {
        language: "english".to_owned(),
        expected_text: expected_text.to_owned(),
        word_error_rate: word_error_rate(expected_text, &actual_text),
        actual_text,
        processing_milliseconds,
        audio_milliseconds,
        realtime_factor: processing_milliseconds as f64 / audio_milliseconds.max(1) as f64,
    })
}

fn read_pcm16_mono_wav(path: &Path) -> Result<(u32, Vec<f32>), String> {
    let bytes = fs::read(path).map_err(|error| error.to_string())?;
    if bytes.len() < 44 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err("benchmark audio is not a WAV file".to_owned());
    }
    let mut cursor = 12_usize;
    let mut format = None;
    let mut data = None;
    while cursor + 8 <= bytes.len() {
        let id = &bytes[cursor..cursor + 4];
        let size = u32::from_le_bytes(
            bytes[cursor + 4..cursor + 8]
                .try_into()
                .map_err(|_| "invalid WAV chunk".to_owned())?,
        ) as usize;
        let start = cursor + 8;
        let end = start
            .checked_add(size)
            .filter(|end| *end <= bytes.len())
            .ok_or_else(|| "truncated WAV chunk".to_owned())?;
        if id == b"fmt " && size >= 16 {
            let audio_format = u16::from_le_bytes([bytes[start], bytes[start + 1]]);
            let channels = u16::from_le_bytes([bytes[start + 2], bytes[start + 3]]);
            let sample_rate = u32::from_le_bytes(
                bytes[start + 4..start + 8]
                    .try_into()
                    .map_err(|_| "invalid WAV sample rate".to_owned())?,
            );
            let bits = u16::from_le_bytes([bytes[start + 14], bytes[start + 15]]);
            format = Some((audio_format, channels, sample_rate, bits));
        } else if id == b"data" {
            data = Some(&bytes[start..end]);
        }
        cursor = end + (size % 2);
    }
    let (audio_format, channels, sample_rate, bits) =
        format.ok_or_else(|| "WAV format chunk is missing".to_owned())?;
    if audio_format != 1 || channels != 1 || bits != 16 {
        return Err("benchmark WAV must use mono PCM16".to_owned());
    }
    let data = data.ok_or_else(|| "WAV data chunk is missing".to_owned())?;
    let samples = data
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]) as f32 / i16::MAX as f32)
        .collect();
    Ok((sample_rate, samples))
}

fn word_error_rate(expected: &str, actual: &str) -> f64 {
    let expected = normalized_words(expected);
    let actual = normalized_words(actual);
    if expected.is_empty() {
        return if actual.is_empty() { 0.0 } else { 1.0 };
    }
    let mut previous: Vec<usize> = (0..=actual.len()).collect();
    for (row, expected_word) in expected.iter().enumerate() {
        let mut current = vec![row + 1];
        for (column, actual_word) in actual.iter().enumerate() {
            current.push(
                (previous[column + 1] + 1)
                    .min(current[column] + 1)
                    .min(previous[column] + usize::from(expected_word != actual_word)),
            );
        }
        previous = current;
    }
    previous[actual.len()] as f64 / expected.len() as f64
}

fn normalized_words(value: &str) -> Vec<String> {
    value
        .split_whitespace()
        .map(|word| {
            word.trim_matches(|value: char| !value.is_alphanumeric())
                .to_lowercase()
        })
        .filter(|word| !word.is_empty())
        .collect()
}

/// Benchmarks deterministic cleanup, routing, and protected-token validation.
#[frb(ignore)]
pub fn run_text_pipeline_benchmark(iterations: u32) -> TextPipelineBenchmarkReport {
    let cases = [
        ("um please send the invoice comma thanks full stop", "clean"),
        (
            "bhai woh invoice bhej dena aaj sorry kal tak chalega",
            "intent",
        ),
        ("email APIKey42 to hello@swar.dev question mark", "intent"),
        ("  preserve   exactly what I said  ", "raw"),
    ];
    let iterations = iterations.clamp(1, 1_000_000);
    let started = Instant::now();
    let mut durations = Vec::with_capacity(iterations as usize * cases.len());
    for _ in 0..iterations {
        for (raw, mode) in cases {
            let operation_started = Instant::now();
            let clean = text_cleanup::clean_transcript(raw, mode);
            let result = enhancement::enhance_transcript(
                raw,
                &clean,
                mode,
                "Benchmark",
                // The benchmark measures the editor, not context assembly.
                "",
                enhancement::EnhancementProviderConfig {
                    provider: "local",
                    endpoint: "",
                    model: "",
                    api_key: "",
                },
            );
            std::hint::black_box(result);
            durations.push(operation_started.elapsed().as_micros() as u64);
        }
    }
    let elapsed = started.elapsed().as_secs_f64();
    durations.sort_unstable();
    let percentile = |percent: usize| {
        durations[(durations.len().saturating_sub(1) * percent / 100)
            .min(durations.len().saturating_sub(1))]
    };
    TextPipelineBenchmarkReport {
        iterations,
        samples: durations.len() as u64,
        p50_microseconds: percentile(50),
        p95_microseconds: percentile(95),
        maximum_microseconds: *durations.last().unwrap_or(&0),
        operations_per_second: durations.len() as f64 / elapsed.max(f64::EPSILON),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn benchmark_returns_all_latency_percentiles() {
        let report = run_text_pipeline_benchmark(2);
        assert_eq!(report.samples, 8);
        assert!(report.p50_microseconds <= report.p95_microseconds);
        assert!(report.p95_microseconds <= report.maximum_microseconds);
        assert!(report.operations_per_second.is_finite());
    }

    #[test]
    fn word_error_rate_handles_insertions_deletions_and_case() {
        assert_eq!(word_error_rate("Hello Swar", "hello swar"), 0.0);
        assert_eq!(word_error_rate("one two", "one three"), 0.5);
        assert_eq!(word_error_rate("one two", "one two three"), 0.5);
    }
}
