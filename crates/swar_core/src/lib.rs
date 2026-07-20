//! Swar's native application core.

pub mod api;
mod asr;
mod audio;
mod dictation;
mod enhancement;
// Heavy cleanup evaluation over a fixed corpus; test-only and feature-gated.
#[cfg(all(test, feature = "embedded-llm"))]
mod eval;
mod frb_generated;
mod insertion;
mod language;
#[cfg(feature = "embedded-llm")]
mod llm;
mod storage;
mod text_cleanup;
