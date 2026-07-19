use swar_core::api::benchmark::run_asr_file_benchmark;

fn main() {
    let arguments = std::env::args().skip(1).collect::<Vec<_>>();
    if arguments.len() != 4 {
        eprintln!("usage: swar_asr_benchmark MODEL WAV LANGUAGE EXPECTED_TEXT_FILE");
        std::process::exit(2);
    }
    let expected = std::fs::read_to_string(&arguments[3]).unwrap_or_else(|error| {
        eprintln!("could not read expected text: {error}");
        std::process::exit(1);
    });
    match run_asr_file_benchmark(&arguments[0], &arguments[1], &arguments[2], expected.trim()) {
        Ok(report) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&report).expect("benchmark report serializes")
            );
            enforce_ceiling(
                "word error rate",
                report.word_error_rate,
                "SWAR_BENCHMARK_MAX_WER",
            );
            enforce_ceiling(
                "real-time factor",
                report.realtime_factor,
                "SWAR_BENCHMARK_MAX_RTF",
            );
        }
        Err(error) => {
            eprintln!("ASR benchmark failed: {error}");
            std::process::exit(1);
        }
    }
}

fn enforce_ceiling(label: &str, actual: f64, variable: &str) {
    let Some(value) = std::env::var(variable).ok() else {
        return;
    };
    let maximum = value.parse::<f64>().unwrap_or_else(|_| {
        eprintln!("{variable} must be a decimal number");
        std::process::exit(2);
    });
    if actual > maximum {
        eprintln!("ASR regression: {label} {actual:.4} exceeded ceiling {maximum:.4}");
        std::process::exit(1);
    }
}
