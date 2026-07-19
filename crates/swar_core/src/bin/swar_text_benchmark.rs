use swar_core::api::benchmark::run_text_pipeline_benchmark;

fn main() {
    let iterations = std::env::args()
        .nth(1)
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(10_000);
    let report = run_text_pipeline_benchmark(iterations);
    println!(
        "{}",
        serde_json::to_string_pretty(&report).expect("benchmark report serializes")
    );
}
