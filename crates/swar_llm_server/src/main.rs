//! Swar offline cleanup helper.
//!
//! A standalone process that owns llama.cpp. It reads line-delimited JSON
//! requests on stdin and writes line-delimited JSON responses on stdout, each
//! response prefixed with a sentinel so llama.cpp's own stdout chatter (if any)
//! can be skipped by the parent. The model is loaded lazily on the first request
//! and kept warm for the life of the process. Closing stdin (parent exits) ends
//! the process, so there is never an orphaned helper.
//!
//! Protocol (one JSON object per line):
//!   parent -> child   {"model":"/path.gguf","system":"...","user":"..."}
//!   parent -> child   {"model":"/path.gguf","prepare":true}      // warm only
//!   child  -> parent   @@SWARLLM@@ {"ok":true,"text":"..."}
//!   child  -> parent   @@SWARLLM@@ {"ok":true,"ready":true}
//!   child  -> parent   @@SWARLLM@@ {"ok":false,"error":"..."}
//!
//! The cleanup prompt and the protected-token validation are NOT here — they
//! live in swar_core. This process only turns (system, user) text into text.

use std::{
    io::{self, BufRead, Write},
    num::NonZeroU32,
    panic::{self, AssertUnwindSafe},
};

use llama_cpp_2::{
    context::params::LlamaContextParams,
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, AddBos, LlamaModel},
    sampling::LlamaSampler,
};
use serde::{Deserialize, Serialize};

/// Prefix that marks a protocol line on stdout. Any stdout line without it (for
/// example a stray ggml log) is ignored by the parent.
const RESPONSE_SENTINEL: &str = "@@SWARLLM@@ ";

/// Context window handed to the model. Cleanup prompts are short; this leaves
/// generous room for the system prompt plus a long dictation.
const CONTEXT_TOKENS: u32 = 4096;
/// Hard ceiling on generated tokens. A cleaned transcript is never long; the cap
/// stops a degenerate model from running away and blowing the latency budget.
const MAX_NEW_TOKENS: usize = 512;
/// Full GPU offload where a backend (Metal) is present; llama.cpp silently falls
/// back to CPU layers when it is not.
const GPU_LAYERS: u32 = 999;

#[derive(Deserialize)]
struct Request {
    model: String,
    #[serde(default)]
    system: String,
    #[serde(default)]
    user: String,
    #[serde(default)]
    prepare: bool,
}

#[derive(Serialize)]
struct Response {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    ready: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl Response {
    fn text(text: String) -> Self {
        Self {
            ok: true,
            text: Some(text),
            ready: None,
            error: None,
        }
    }
    fn ready() -> Self {
        Self {
            ok: true,
            text: None,
            ready: Some(true),
            error: None,
        }
    }
    fn error(message: String) -> Self {
        Self {
            ok: false,
            text: None,
            ready: None,
            error: Some(message),
        }
    }
}

/// The warm state. The backend must be initialised exactly once per process; the
/// model is kept resident so repeated cleanups do not reload ~2 GB of weights.
struct Warm {
    backend: LlamaBackend,
    model_path: String,
    model: LlamaModel,
}

fn main() {
    // Silence llama.cpp/ggml's own logging so it can never interleave with the
    // protocol on stdout. Any diagnostics we emit go to stderr.
    llama_cpp_2::send_logs_to_tracing(llama_cpp_2::LogOptions::default().with_logs_enabled(false));

    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut warm: Option<Warm> = None;

    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let response = match serde_json::from_str::<Request>(line) {
            Ok(request) => handle(&mut warm, &request),
            Err(error) => Response::error(format!("bad request json: {error}")),
        };
        write_response(&mut stdout, &response);
    }
    // stdin closed (parent gone): drop the warm model before exit so ggml's
    // Metal finalizer does not assert on still-live resource sets.
    warm = None;
    let _ = warm;
}

fn write_response(stdout: &mut io::Stdout, response: &Response) {
    let json = serde_json::to_string(response).unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"response serialization failed\"}".to_owned()
    });
    // A single write with an explicit flush keeps the line atomic for the parent.
    let _ = writeln!(stdout, "{RESPONSE_SENTINEL}{json}");
    let _ = stdout.flush();
}

fn handle(warm: &mut Option<Warm>, request: &Request) -> Response {
    // Catch a panic inside llama.cpp: it would otherwise unwind through the C
    // frame (undefined behaviour). Drop the possibly-corrupt model and report a
    // recoverable error so the parent falls back to deterministic cleanup.
    let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
        let state = ensure_model(warm, &request.model)?;
        if request.prepare {
            return Ok(None);
        }
        generate_once(&state.backend, &state.model, &request.system, &request.user).map(Some)
    }));
    match outcome {
        Ok(Ok(Some(text))) => Response::text(text),
        Ok(Ok(None)) => Response::ready(),
        Ok(Err(error)) => Response::error(error),
        Err(_) => {
            *warm = None;
            Response::error("the offline LLM panicked during generation".to_owned())
        }
    }
}

/// Ensures the model at `model_path` is warm, loading it if necessary.
fn ensure_model<'a>(warm: &'a mut Option<Warm>, model_path: &str) -> Result<&'a Warm, String> {
    let needs_load = warm
        .as_ref()
        .map(|state| state.model_path != model_path)
        .unwrap_or(true);
    if needs_load {
        if model_path.trim().is_empty() {
            return Err("no model path was provided".to_owned());
        }
        let backend =
            LlamaBackend::init().map_err(|error| format!("llama backend init failed: {error}"))?;
        let params = LlamaModelParams::default().with_n_gpu_layers(GPU_LAYERS);
        let model = LlamaModel::load_from_file(&backend, model_path, &params)
            .map_err(|error| format!("could not load the offline LLM: {error}"))?;
        *warm = Some(Warm {
            backend,
            model_path: model_path.to_owned(),
            model,
        });
    }
    Ok(warm.as_ref().expect("model was just ensured"))
}

/// Runs one deterministic (greedy) generation for a ChatML-formatted prompt.
fn generate_once(
    backend: &LlamaBackend,
    model: &LlamaModel,
    system: &str,
    user: &str,
) -> Result<String, String> {
    // ChatML — the format Swar's shipped instruct model expects. Building it
    // directly (rather than via the model's embedded template) keeps generation
    // deterministic and independent of template quirks in a given GGUF.
    let prompt = format!(
        "<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"
    );

    // `str_to_token` parses special tokens, so the ChatML markers tokenize
    // correctly. No BOS: the ChatML markers already delimit the turn.
    let mut tokens = model
        .str_to_token(&prompt, AddBos::Never)
        .map_err(|error| format!("tokenisation failed: {error}"))?;
    // Never let the prompt crowd out room to answer.
    let ceiling = CONTEXT_TOKENS as usize - MAX_NEW_TOKENS;
    if tokens.len() > ceiling {
        // Keep the most recent tokens (the user text sits at the end).
        tokens.drain(0..tokens.len() - ceiling);
    }

    let context_params = LlamaContextParams::default().with_n_ctx(NonZeroU32::new(CONTEXT_TOKENS));
    let mut context = model
        .new_context(backend, context_params)
        .map_err(|error| format!("could not create the LLM context: {error}"))?;

    // Decode the prompt. Only the final token needs logits (we sample from it).
    let mut batch = LlamaBatch::new(tokens.len().max(1), 1);
    let last = tokens.len() as i32 - 1;
    for (position, token) in tokens.iter().enumerate() {
        batch
            .add(*token, position as i32, &[0], position as i32 == last)
            .map_err(|error| format!("batch build failed: {error}"))?;
    }
    context
        .decode(&mut batch)
        .map_err(|error| format!("prompt decode failed: {error}"))?;

    let mut sampler = LlamaSampler::greedy();
    let mut produced: Vec<u8> = Vec::new();
    let mut position = tokens.len() as i32;
    let mut logits_index = batch.n_tokens() - 1;
    for _ in 0..MAX_NEW_TOKENS {
        let token = sampler.sample(&context, logits_index);
        sampler.accept(token);
        if model.is_eog_token(token) {
            break;
        }
        // Collect raw bytes and decode at the end: a multi-byte character can
        // straddle two tokens, so per-token UTF-8 decoding would corrupt it.
        // `special=false` keeps any stray control tokens out of the output.
        if let Ok(bytes) = model.token_to_piece_bytes(token, 32, false, None) {
            produced.extend_from_slice(&bytes);
        }
        batch.clear();
        batch
            .add(token, position, &[0], true)
            .map_err(|error| format!("batch build failed: {error}"))?;
        position += 1;
        context
            .decode(&mut batch)
            .map_err(|error| format!("token decode failed: {error}"))?;
        logits_index = 0;
    }

    Ok(String::from_utf8_lossy(&produced).trim().to_owned())
}
