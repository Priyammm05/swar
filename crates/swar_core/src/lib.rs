//! Swar's native application core.

pub mod api;
mod asr;
// Client for the out-of-process fast ASR helper (`swar_asr_server`). No ONNX
// links into this framework; recognition falls back to whisper if it is absent.
mod asr_client;
mod audio;
mod context;
mod dictation;
mod enhancement;
// Heavy cleanup evaluation over a fixed corpus; test-only. Runs the real cleanup
// helper and is opt-in at runtime (see `eval.rs`).
#[cfg(test)]
mod eval;
mod frb_generated;
mod insertion;
// Client for the out-of-process cleanup helper (`swar_llm_server`). No llama.cpp
// links into this framework, so whisper.cpp's ggml never collides with it.
mod llm_client;
mod storage;
mod text_cleanup;
