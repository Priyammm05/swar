//! Offline cleanup evaluation over a fixed corpus of ~200 short and long
//! sentences (English / Hindi / Hinglish). It is heavy — it drives the real
//! `swar_llm_server` helper (which loads the ~2 GB cleanup model) and runs one
//! generation per sentence — so it is opt-in at runtime: it needs both
//! `SWAR_LLM_EVAL=1` and `SWAR_LLM_SERVER=<path to the built helper>`, and skips
//! loudly otherwise. It is the regression that proves cleanup never produces
//! degenerate output (empties, truncation, repetition blow-ups, or flipped
//! negation) across a wide spread of real-shaped dictations.

use std::time::Instant;

use crate::enhancement::{enhance_transcript, EnhancementProviderConfig};

const CORPUS: &str = include_str!("eval/cleanup_corpus.txt");

/// Negation markers whose disappearance would flip a sentence's meaning — the
/// most damaging cleanup failure. Matched as whole lowercase words.
const NEGATIONS: &[&str] = &[
    "not", "no", "never", "don't", "dont", "cannot", "can't", "cant", "n't", "without", "nahi",
    "mat", "mana", "bina", "nahin",
];

fn corpus_sentences() -> Vec<&'static str> {
    CORPUS
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .collect()
}

fn lowercase_words(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric() && c != '\'')
        .filter(|word| !word.is_empty())
        .map(|word| word.to_ascii_lowercase())
        .collect()
}

fn has_negation(text: &str) -> bool {
    let words = lowercase_words(text);
    words.iter().any(|word| NEGATIONS.contains(&word.as_str()))
}

/// A representative context block, shaped exactly like the one `crate::context`
/// assembles in production: vocabulary, recent dictations, and surrounding field
/// text with the caret marker.
///
/// Set `SWAR_LLM_EVAL_CONTEXT=0` to measure the no-context baseline instead.
/// This matters because the context block is the thing most likely to make a 3B
/// model wander — echoing the reference material, or answering it instead of
/// editing the transcript. Evaluating cleanup without it would no longer be
/// evaluating what actually ships.
fn eval_local_context() -> &'static str {
    if std::env::var("SWAR_LLM_EVAL_CONTEXT").as_deref() == Ok("0") {
        return "";
    }
    "Known terms: Oynix, Niyo, Fi\n\n\
The speaker's recent dictations, newest first:\n\
- Please push the branch once CI is green\n\
- Kal ka standup 10 baje hai, calendar check kar lena\n\
- The invoice for March is still pending approval\n\
- Let's ship the connector after the review\n\
- Team ko bata dena release Friday ko hai\n\n\
Text already in the field, with <CURSOR> where the new text goes:\n\
Thanks for the update on the migration. <CURSOR>"
}

#[test]
fn cleanup_never_degenerates_across_the_corpus() {
    if std::env::var("SWAR_LLM_EVAL").is_err() {
        eprintln!(
            "SKIP cleanup_eval: set SWAR_LLM_EVAL=1 to run the ~200-sentence LLM eval (loads the ~2 GB model)"
        );
        return;
    }
    if std::env::var("SWAR_LLM_SERVER").is_err() {
        eprintln!(
            "SKIP cleanup_eval: set SWAR_LLM_SERVER=<path to the built swar_llm_server> so the helper can be reached"
        );
        return;
    }
    let Some(model) = crate::api::models::embedded_llm_model_path() else {
        eprintln!("SKIP cleanup_eval: embedded LLM model is not installed; nothing evaluated");
        return;
    };
    let model = model.to_string_lossy().into_owned();

    let sentences = corpus_sentences();
    assert!(
        sentences.len() >= 200,
        "corpus must hold at least 200 sentences, found {}",
        sentences.len()
    );

    let mut applied = 0_usize;
    let mut fell_back = 0_usize;
    let mut short = 0_usize;
    let mut long = 0_usize;
    let mut latencies_ms: Vec<u128> = Vec::with_capacity(sentences.len());
    let mut failures: Vec<String> = Vec::new();

    for sentence in &sentences {
        let word_count = sentence.split_whitespace().count();
        if word_count <= 6 {
            short += 1;
        } else {
            long += 1;
        }

        let started = Instant::now();
        let outcome = enhance_transcript(
            sentence,
            sentence,
            "clean",
            "",
            eval_local_context(),
            EnhancementProviderConfig {
                provider: "embedded-llm",
                endpoint: "",
                model: &model,
                api_key: "",
            },
        );
        latencies_ms.push(started.elapsed().as_millis());

        if outcome.validation_fallback {
            fell_back += 1;
        } else if outcome.applied {
            applied += 1;
        }

        let output = outcome.text.trim();

        // 1) Never empty.
        if output.is_empty() {
            failures.push(format!("empty output for: {sentence:?}"));
            continue;
        }
        // 2) Never truncated or blown up (repetition collapse). The final text is
        //    guarded by the protected-token validator, so a wild ratio signals a
        //    real problem even after the safety fallback.
        let out_words = output.split_whitespace().count().max(1);
        let ratio = out_words as f64 / word_count.max(1) as f64;
        if !(0.3..=3.5).contains(&ratio) {
            failures.push(format!(
                "suspicious length ratio {ratio:.2} ({word_count} -> {out_words} words) for: {sentence:?} => {output:?}"
            ));
        }
        // 3) Negation must survive — flipping it is the worst failure.
        if has_negation(sentence) && !has_negation(output) {
            failures.push(format!(
                "negation lost cleaning: {sentence:?} => {output:?}"
            ));
        }
    }

    latencies_ms.sort_unstable();
    let median = latencies_ms[latencies_ms.len() / 2];
    let p95 = latencies_ms[latencies_ms.len() * 95 / 100];
    let max = *latencies_ms.last().unwrap();

    eprintln!("=== Swar cleanup eval ===");
    eprintln!(
        "sentences: {} (short<=6w: {short}, long: {long})",
        sentences.len()
    );
    eprintln!("llm applied changes: {applied}, safety fallback: {fell_back}");
    eprintln!("latency ms: median {median}, p95 {p95}, max {max}");
    eprintln!("failures: {}", failures.len());

    assert!(
        failures.is_empty(),
        "cleanup produced degenerate output:\n{}",
        failures.join("\n")
    );
}
