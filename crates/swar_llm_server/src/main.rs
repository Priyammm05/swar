//! Swar offline cleanup helper.
//!
//! A standalone process that owns llama.cpp. It reads line-delimited JSON
//! requests on stdin and writes line-delimited JSON responses on stdout, each
//! response prefixed with a sentinel so llama.cpp's own stdout chatter (if any)
//! can be skipped by the parent. The model is loaded lazily on the first request
//! and kept warm for the life of the process, along with its context and the
//! decoded KV prefix of the system prompt. Closing stdin (parent exits) ends the
//! process, so there is never an orphaned helper.
//!
//! Protocol (one JSON object per line):
//!   parent -> child   {"model":"/path.gguf","system":"...","user":"..."}
//!   parent -> child   {"model":"/path.gguf","system":"...","prepare":true}
//!                       // warm only; `system` also pre-decodes the KV prefix
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
    context::{params::LlamaContextParams, LlamaContext},
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

fn main() {
    // Silence llama.cpp/ggml's own logging so it can never interleave with the
    // protocol on stdout. Any diagnostics we emit go to stderr.
    llama_cpp_2::send_logs_to_tracing(llama_cpp_2::LogOptions::default().with_logs_enabled(false));

    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let mut stdout = io::stdout();

    // The backend must be initialised exactly once per process, so it is created
    // here rather than per model load.
    let backend = match LlamaBackend::init() {
        Ok(backend) => backend,
        Err(error) => {
            write_response(
                &mut stdout,
                &Response::error(format!("llama backend init failed: {error}")),
            );
            return;
        }
    };

    // A session owns one loaded model plus its live context. It runs until a
    // request names a different model (returned here, to be served by the next
    // session) or stdin closes. Keeping the model and context as locals lets the
    // context borrow the model normally — `LlamaContext<'a>` holds `&'a
    // LlamaModel`, so the pair cannot live together in a struct — and it means
    // both are dropped before exit, which ggml's Metal finalizer requires.
    let mut pending = match next_request(&mut lines, &mut stdout) {
        Some(request) => request,
        None => return,
    };
    while let Some(request) = run_session(&backend, pending, &mut lines, &mut stdout) {
        pending = request;
    }
}

/// Reads lines until one parses as a request. A malformed line is reported and
/// skipped rather than ending the process. Returns `None` when stdin closes.
fn next_request(
    lines: &mut io::Lines<io::StdinLock<'_>>,
    stdout: &mut io::Stdout,
) -> Option<Request> {
    for line in lines.by_ref() {
        let Ok(line) = line else { return None };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        match serde_json::from_str::<Request>(line) {
            Ok(request) => return Some(request),
            Err(error) => write_response(
                stdout,
                &Response::error(format!("bad request json: {error}")),
            ),
        }
    }
    None
}

fn write_response(stdout: &mut io::Stdout, response: &Response) {
    let json = serde_json::to_string(response).unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"response serialization failed\"}".to_owned()
    });
    // A single write with an explicit flush keeps the line atomic for the parent.
    let _ = writeln!(stdout, "{RESPONSE_SENTINEL}{json}");
    let _ = stdout.flush();
}

/// Serves every request for one model. Returns the first request naming a
/// different model, so the caller can reload; returns `None` when stdin closes.
fn run_session(
    backend: &LlamaBackend,
    first: Request,
    lines: &mut io::Lines<io::StdinLock<'_>>,
    stdout: &mut io::Stdout,
) -> Option<Request> {
    let model_path = first.model.clone();
    if model_path.trim().is_empty() {
        write_response(
            stdout,
            &Response::error("no model path was provided".to_owned()),
        );
        return next_request(lines, stdout);
    }

    let params = LlamaModelParams::default().with_n_gpu_layers(GPU_LAYERS);
    let model = match LlamaModel::load_from_file(backend, &model_path, &params) {
        Ok(model) => model,
        Err(error) => {
            write_response(
                stdout,
                &Response::error(format!("could not load the offline LLM: {error}")),
            );
            return next_request(lines, stdout);
        }
    };
    let context_params = LlamaContextParams::default().with_n_ctx(NonZeroU32::new(CONTEXT_TOKENS));
    let context = match model.new_context(backend, context_params) {
        Ok(context) => context,
        Err(error) => {
            write_response(
                stdout,
                &Response::error(format!("could not create the LLM context: {error}")),
            );
            return next_request(lines, stdout);
        }
    };

    let mut session = Session {
        model: &model,
        context,
        cached_system: String::new(),
        prefix_tokens: 0,
    };

    let mut request = first;
    loop {
        if request.model != model_path {
            return Some(request);
        }
        let (response, poisoned) = session.handle(&request);
        write_response(stdout, &response);
        // A panic may have left llama.cpp's state inconsistent. End the session so
        // the model and context are dropped and rebuilt from scratch.
        if poisoned {
            return next_request(lines, stdout);
        }
        request = next_request(lines, stdout)?;
    }
}

/// One loaded model, its live context, and the decoded system-prompt prefix.
///
/// The context is kept across requests so the system turn is decoded once and
/// then reused: only the (short) user turn is decoded per dictation. Rebuilding
/// the context every time — as this helper used to — re-ran the entire system
/// prompt through the model on every request, which dominated the latency.
struct Session<'a> {
    model: &'a LlamaModel,
    context: LlamaContext<'a>,
    cached_system: String,
    prefix_tokens: u32,
}

impl Session<'_> {
    fn handle(&mut self, request: &Request) -> (Response, bool) {
        // Catch a panic inside llama.cpp: it would otherwise unwind through the C
        // frame (undefined behaviour). Report a recoverable error so the parent
        // falls back to deterministic cleanup.
        let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
            if request.prepare {
                // Warming with the real system prompt also pays the prefix decode
                // up front, so the first dictation is as fast as the rest.
                if !request.system.is_empty() {
                    self.ensure_prefix(&request.system)?;
                }
                return Ok(None);
            }
            self.generate(&request.system, &request.user).map(Some)
        }));
        match outcome {
            Ok(Ok(Some(text))) => (Response::text(text), false),
            Ok(Ok(None)) => (Response::ready(), false),
            Ok(Err(error)) => (Response::error(error), false),
            Err(_) => (
                Response::error("the offline LLM panicked during generation".to_owned()),
                true,
            ),
        }
    }

    /// Leaves the KV cache holding exactly the decoded system turn for `system`,
    /// reusing it when the text is unchanged.
    fn ensure_prefix(&mut self, system: &str) -> Result<(), String> {
        if self.prefix_tokens > 0 && self.cached_system == system {
            // Same system prompt: keep its decoded tokens and drop only the
            // previous request's user turn and reply.
            self.context
                .clear_kv_cache_seq(Some(0), Some(self.prefix_tokens), None)
                .map_err(|error| format!("kv cache trim failed: {error}"))?;
            return Ok(());
        }

        // Different (or first) system prompt: rebuild the prefix from scratch.
        self.context.clear_kv_cache();
        self.cached_system.clear();
        self.prefix_tokens = 0;

        // ChatML — the format Swar's shipped instruct model expects. Building it
        // directly (rather than via the model's embedded template) keeps
        // generation deterministic and independent of template quirks in a given
        // GGUF. `str_to_token` parses special tokens, so the markers tokenize
        // correctly. No BOS: the ChatML markers already delimit the turn.
        let prefix = format!("<|im_start|>system\n{system}<|im_end|>\n");
        let tokens = self
            .model
            .str_to_token(&prefix, AddBos::Never)
            .map_err(|error| format!("tokenisation failed: {error}"))?;
        if tokens.len() >= CONTEXT_TOKENS as usize - MAX_NEW_TOKENS {
            return Err("the cleanup system prompt does not fit the context".to_owned());
        }
        let mut batch = LlamaBatch::new(tokens.len().max(1), 1);
        let last = tokens.len() as i32 - 1;
        for (position, token) in tokens.iter().enumerate() {
            batch
                .add(*token, position as i32, &[0], position as i32 == last)
                .map_err(|error| format!("batch build failed: {error}"))?;
        }
        self.context
            .decode(&mut batch)
            .map_err(|error| format!("system prompt decode failed: {error}"))?;
        self.prefix_tokens = tokens.len() as u32;
        self.cached_system = system.to_owned();
        Ok(())
    }

    /// Runs one deterministic (greedy) generation on top of the cached prefix.
    fn generate(&mut self, system: &str, user: &str) -> Result<String, String> {
        self.ensure_prefix(system)?;
        // Copied out so the immutable model borrow does not overlap the mutable
        // context borrows below.
        let model = self.model;
        let start = self.prefix_tokens as usize;

        let turn = format!("<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n");
        let mut tokens = model
            .str_to_token(&turn, AddBos::Never)
            .map_err(|error| format!("tokenisation failed: {error}"))?;
        // Never let the user turn crowd out room to answer. Dictations are far
        // shorter than this, so the drain is a guard rather than a normal path.
        let room = (CONTEXT_TOKENS as usize - MAX_NEW_TOKENS).saturating_sub(start);
        if tokens.len() > room {
            // Keep the tail: it carries the assistant marker generation resumes from.
            tokens.drain(0..tokens.len() - room);
        }

        // Decode the user turn. Only its final token needs logits (we sample from it).
        let mut batch = LlamaBatch::new(tokens.len().max(1), 1);
        let last = tokens.len() as i32 - 1;
        for (offset, token) in tokens.iter().enumerate() {
            batch
                .add(*token, (start + offset) as i32, &[0], offset as i32 == last)
                .map_err(|error| format!("batch build failed: {error}"))?;
        }
        self.context
            .decode(&mut batch)
            .map_err(|error| format!("prompt decode failed: {error}"))?;

        let mut sampler = LlamaSampler::greedy();
        let mut produced: Vec<u8> = Vec::new();
        let mut position = (start + tokens.len()) as i32;
        let mut logits_index = batch.n_tokens() - 1;
        for _ in 0..MAX_NEW_TOKENS {
            let token = sampler.sample(&self.context, logits_index);
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
            self.context
                .decode(&mut batch)
                .map_err(|error| format!("token decode failed: {error}"))?;
            logits_index = 0;
        }

        Ok(String::from_utf8_lossy(&produced).trim().to_owned())
    }
}
