//! Swar fast offline ASR helper.
//!
//! A standalone process that owns the fast ONNX speech engines and turns audio
//! into text over a line-delimited stdio protocol — the same isolation pattern as
//! the cleanup LLM helper. It hosts two engines, routed by language:
//!
//!   - Parakeet (sherpa-onnx) for English / European speech
//!   - IndicConformer (ort) for Hindi and Indian languages
//!
//! Both run ~20-30x faster than whisper. The parent writes the captured 16 kHz
//! mono audio to a temp WAV and sends its path; the helper replies with text.
//!
//! Protocol (one JSON object per line):
//!
//!   - parent -> child: `{"wav":"/tmp/x.wav","language":"hindi","parakeet_dir":"..","indic_dir":".."}`
//!   - child  -> parent: `@@SWARASR@@ {"ok":true,"text":"..."}`
//!   - child  -> parent: `@@SWARASR@@ {"ok":false,"error":"..."}`

mod indic;
mod mel;

use std::{
    io::{self, BufRead, Write},
    path::PathBuf,
};

use serde::Deserialize;

use indic::IndicConformer;

const RESPONSE_SENTINEL: &str = "@@SWARASR@@ ";

#[derive(Deserialize)]
struct Request {
    wav: String,
    #[serde(default)]
    language: String,
    #[serde(default)]
    parakeet_dir: String,
    #[serde(default)]
    indic_dir: String,
}

/// Warm engines, loaded lazily on first use and kept resident.
#[derive(Default)]
struct Engines {
    parakeet: Option<(String, sherpa_rs::transducer::TransducerRecognizer)>,
    indic: Option<(String, IndicConformer)>,
}

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut engines = Engines::default();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let reply = match serde_json::from_str::<Request>(line) {
            Ok(req) => match handle(&mut engines, &req) {
                Ok(text) => ok(&text),
                Err(e) => err(&e),
            },
            Err(e) => err(&format!("bad request json: {e}")),
        };
        let _ = writeln!(stdout, "{RESPONSE_SENTINEL}{reply}");
        let _ = stdout.flush();
    }
}

fn handle(engines: &mut Engines, req: &Request) -> Result<String, String> {
    let samples = read_wav_16k_mono(&req.wav)?;
    if samples.is_empty() {
        return Ok(String::new());
    }
    match route(&req.language) {
        Route::Parakeet => transcribe_parakeet(engines, &req.parakeet_dir, &samples),
        Route::Indic(lang) => transcribe_indic(engines, &req.indic_dir, &samples, lang),
    }
}

enum Route {
    Parakeet,
    Indic(&'static str),
}

/// Maps a Swar language mode (or ISO code) to an engine + IndicConformer code.
/// Auto/unset default to Parakeet (English) here — the caller resolves Auto to a
/// concrete language via detection before it reaches this router, so this is only
/// the safety default when it does not. Explicit Hindi/Hinglish use IndicConformer.
fn route(language: &str) -> Route {
    match language.trim().to_ascii_lowercase().as_str() {
        "english" | "en" | "automatic" | "auto" | "" => Route::Parakeet,
        "hindi" | "hi" | "hinglish" => Route::Indic("hi"),
        "tamil" | "ta" => Route::Indic("ta"),
        "telugu" | "te" => Route::Indic("te"),
        "bengali" | "bn" => Route::Indic("bn"),
        "kannada" | "kn" => Route::Indic("kn"),
        "malayalam" | "ml" => Route::Indic("ml"),
        "marathi" | "mr" => Route::Indic("mr"),
        "gujarati" | "gu" => Route::Indic("gu"),
        "punjabi" | "pa" => Route::Indic("pa"),
        "odia" | "or" => Route::Indic("or"),
        "urdu" | "ur" => Route::Indic("ur"),
        // Unknown: try IndicConformer Hindi rather than fail.
        _ => Route::Indic("hi"),
    }
}

fn transcribe_parakeet(
    engines: &mut Engines,
    dir: &str,
    samples: &[f32],
) -> Result<String, String> {
    if dir.trim().is_empty() {
        return Err("no parakeet_dir provided".to_owned());
    }
    let needs = engines
        .parakeet
        .as_ref()
        .map(|(d, _)| d != dir)
        .unwrap_or(true);
    if needs {
        let d = PathBuf::from(dir);
        let cfg = sherpa_rs::transducer::TransducerConfig {
            encoder: d.join("encoder.int8.onnx").to_string_lossy().into_owned(),
            decoder: d.join("decoder.int8.onnx").to_string_lossy().into_owned(),
            joiner: d.join("joiner.int8.onnx").to_string_lossy().into_owned(),
            tokens: d.join("tokens.txt").to_string_lossy().into_owned(),
            model_type: "nemo_transducer".into(),
            num_threads: 4,
            ..Default::default()
        };
        let rec = sherpa_rs::transducer::TransducerRecognizer::new(cfg)
            .map_err(|e| format!("parakeet load: {e}"))?;
        engines.parakeet = Some((dir.to_owned(), rec));
    }
    let (_, rec) = engines.parakeet.as_mut().expect("just loaded");
    Ok(rec.transcribe(16000, samples).trim().to_owned())
}

fn transcribe_indic(
    engines: &mut Engines,
    dir: &str,
    samples: &[f32],
    lang: &str,
) -> Result<String, String> {
    if dir.trim().is_empty() {
        return Err("no indic_dir provided".to_owned());
    }
    let needs = engines
        .indic
        .as_ref()
        .map(|(d, _)| d != dir)
        .unwrap_or(true);
    if needs {
        let engine = IndicConformer::new(PathBuf::from(dir))?;
        engines.indic = Some((dir.to_owned(), engine));
    }
    let (_, engine) = engines.indic.as_mut().expect("just loaded");
    engine.transcribe(samples, lang)
}

/// Reads a WAV as mono f32 at 16 kHz. The parent always writes 16 kHz mono, so
/// this only downmixes if needed and does not resample.
fn read_wav_16k_mono(path: &str) -> Result<Vec<f32>, String> {
    let mut reader = hound::WavReader::open(path).map_err(|e| format!("open wav: {e}"))?;
    let spec = reader.spec();
    let ch = spec.channels.max(1) as usize;
    let raw: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => {
            let scale = 1.0 / (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .map(|s| s.unwrap_or(0) as f32 * scale)
                .collect()
        }
        hound::SampleFormat::Float => reader.samples::<f32>().map(|s| s.unwrap_or(0.0)).collect(),
    };
    if ch <= 1 {
        return Ok(raw);
    }
    Ok(raw
        .chunks(ch)
        .map(|frame| frame.iter().sum::<f32>() / ch as f32)
        .collect())
}

fn ok(text: &str) -> String {
    serde_json::json!({"ok": true, "text": text}).to_string()
}
fn err(message: &str) -> String {
    serde_json::json!({"ok": false, "error": message}).to_string()
}
