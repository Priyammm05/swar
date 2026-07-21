//! Scores an ASR corpus case by case and reports one JSON line per case.
//!
//! Kept separate from `swar_asr_benchmark`, which gates a handful of fixed cases
//! against a ceiling. This one is for volume: it walks a manifest of saved WAVs
//! and prints results a driver can aggregate by utterance length.
//!
//! The fixtures are *saved*, never regenerated. The old suite synthesised its
//! audio with `say` on every run, so two runs of identical code compared
//! different recordings and the same case read anywhere from 0.118 to 0.809.

use swar_core::api::benchmark::{run_asr_file_benchmark, run_fast_asr_file_benchmark};

fn main() {
    let arguments = std::env::args().skip(1).collect::<Vec<_>>();
    // The whisper model path is required only by the whisper engine; the fast
    // helper finds its own models through the environment.
    if arguments.len() < 2 || (arguments[0] == "whisper" && arguments.len() < 3) {
        eprintln!("usage: swar_corpus_benchmark ENGINE MANIFEST_JSONL [WHISPER_MODEL]");
        eprintln!("  ENGINE: fast | whisper   (WHISPER_MODEL required for whisper)");
        std::process::exit(2);
    }
    let engine = arguments[0].as_str();
    let manifest = std::fs::read_to_string(&arguments[1]).unwrap_or_else(|error| {
        eprintln!("could not read manifest: {error}");
        std::process::exit(1);
    });
    let model = arguments.get(2).cloned().unwrap_or_default();

    for line in manifest.lines().filter(|line| !line.trim().is_empty()) {
        let Some(case) = ManifestRow::parse(line) else {
            // Loudly: a silently skipped row reads as "the corpus scored clean".
            eprintln!("unparsable manifest row: {line}");
            std::process::exit(1);
        };
        let expected = match std::fs::read_to_string(&case.text) {
            Ok(text) => text.trim().to_owned(),
            Err(error) => {
                println!("{{\"id\":\"{}\",\"error\":\"{error}\"}}", case.id);
                continue;
            }
        };
        let outcome = match engine {
            "fast" => run_fast_asr_file_benchmark(&case.wav, &expected),
            _ => run_asr_file_benchmark(&model, &case.wav, "english", &expected),
        };
        match outcome {
            Ok(report) => println!(
                "{{\"id\":\"{}\",\"words\":{},\"wer\":{:.4},\"ms\":{},\"audio_ms\":{},\"rtf\":{:.4}}}",
                case.id,
                expected.split_whitespace().count(),
                report.word_error_rate,
                report.processing_milliseconds,
                report.audio_milliseconds,
                report.realtime_factor
            ),
            Err(error) => println!(
                "{{\"id\":\"{}\",\"error\":\"{}\"}}",
                case.id,
                error.replace('"', "'")
            ),
        }
    }
}

struct ManifestRow {
    id: String,
    wav: String,
    text: String,
}

impl ManifestRow {
    /// Minimal field pull, so the benchmark needs no JSON dependency.
    fn parse(line: &str) -> Option<Self> {
        Some(Self {
            id: field(line, "id")?,
            wav: field(line, "wav")?,
            text: field(line, "text")?,
        })
    }
}

/// Pulls one string field, tolerating the whitespace `json.dumps` writes after
/// the colon by default.
fn field(line: &str, name: &str) -> Option<String> {
    let key = format!("\"{name}\":");
    let after_key = line.find(&key)? + key.len();
    let rest = line[after_key..].trim_start();
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    Some(rest[..end].to_owned())
}
