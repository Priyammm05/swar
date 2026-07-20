//! Swar's native application core.

pub mod api;
mod asr;
mod audio;
mod dictation;
mod enhancement;
mod frb_generated;
mod insertion;
mod language;
#[cfg(feature = "embedded-llm")]
mod llm;
mod storage;
mod text_cleanup;
