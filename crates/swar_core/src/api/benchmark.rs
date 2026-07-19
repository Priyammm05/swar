use std::time::Instant;

use flutter_rust_bridge::frb;
use serde::Serialize;

use crate::{enhancement, text_cleanup};

#[derive(Clone, Debug, Serialize)]
pub struct TextPipelineBenchmarkReport {
    pub iterations: u32,
    pub samples: u64,
    pub p50_microseconds: u64,
    pub p95_microseconds: u64,
    pub maximum_microseconds: u64,
    pub operations_per_second: f64,
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
            let result = enhancement::enhance_transcript(raw, &clean, mode);
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
}
