//! Optional in-process LLM for offline transcript cleanup (embedded llama.cpp).
//!
//! Gated behind the `embedded-llm` feature. This mirrors the ASR worker in
//! `asr/model_registry.rs`: a single dedicated thread owns the llama.cpp backend
//! and a warm model, serialises all generation, isolates FFI panics, and applies
//! a watchdog so a wedged native call can never hang the caller. Nothing here is
//! Swar-policy: the cleanup prompt and the protected-token validation live in
//! `enhancement.rs`. This module only turns (system, user) text into model text.

use std::{
    num::NonZeroU32,
    panic::{self, AssertUnwindSafe},
    sync::{
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
        LazyLock,
    },
    thread,
    time::Duration,
};

use llama_cpp_2::{
    context::params::LlamaContextParams,
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, AddBos, LlamaModel},
    sampling::LlamaSampler,
};

static LLM: LazyLock<LlmRegistry> = LazyLock::new(LlmRegistry::spawn);

// `prepare`/`unload` (and their timeouts and command variants) are the module's
// warm-up/teardown API. They are wired in when the embedded provider is selected
// from Settings; allow them to exist ahead of that wiring without a warning.
#[allow(dead_code)]
const LOAD_TIMEOUT: Duration = Duration::from_secs(120);
const GENERATE_TIMEOUT: Duration = Duration::from_secs(120);
#[allow(dead_code)]
const UNLOAD_TIMEOUT: Duration = Duration::from_secs(30);

/// Context window handed to the model. Cleanup prompts are short; this leaves
/// generous room for the system prompt plus a long dictation.
const CONTEXT_TOKENS: u32 = 4096;
/// Hard ceiling on generated tokens. A cleaned transcript is never long; the cap
/// stops a degenerate model from running away and blowing the latency budget.
const MAX_NEW_TOKENS: usize = 512;
/// Full GPU offload where a backend (Metal) is present; llama.cpp silently falls
/// back to CPU layers when it is not.
const GPU_LAYERS: u32 = 999;

#[allow(dead_code)]
enum LlmCommand {
    Prepare {
        model_path: String,
        response: Sender<Result<(), String>>,
    },
    Generate {
        model_path: String,
        system: String,
        user: String,
        response: Sender<Result<String, String>>,
    },
    Unload {
        response: Sender<()>,
    },
}

struct LlmRegistry {
    commands: Sender<LlmCommand>,
}

impl LlmRegistry {
    fn spawn() -> Self {
        let (commands, receiver) = mpsc::channel();
        thread::Builder::new()
            .name("swar-llm-worker".to_owned())
            .spawn(move || run_worker(receiver))
            .expect("the dedicated LLM worker must start");
        Self { commands }
    }

    fn send<T>(
        &self,
        make: impl FnOnce(Sender<T>) -> LlmCommand,
        timeout: Duration,
        action: &'static str,
    ) -> Result<T, String> {
        let (response, result) = mpsc::channel();
        self.commands
            .send(make(response))
            .map_err(|_| "the LLM worker is unavailable".to_owned())?;
        result.recv_timeout(timeout).map_err(|error| match error {
            RecvTimeoutError::Timeout => format!("the LLM worker timed out while {action}"),
            RecvTimeoutError::Disconnected => format!("the LLM worker stopped while {action}"),
        })
    }
}

/// Loads the model into the warm worker before the first cleanup so the first
/// dictation does not pay the multi-hundred-millisecond load.
#[allow(dead_code)]
pub(crate) fn prepare(model_path: &str) -> Result<(), String> {
    LLM.send(
        |response| LlmCommand::Prepare {
            model_path: model_path.to_owned(),
            response,
        },
        LOAD_TIMEOUT,
        "loading the model",
    )?
}

/// Cleans one transcript. `system` is the cleanup instruction, `user` is the
/// text to edit. Returns the model's edited text (unvalidated — the caller must
/// still run it through the protected-token validator).
pub(crate) fn generate(model_path: &str, system: &str, user: &str) -> Result<String, String> {
    LLM.send(
        |response| LlmCommand::Generate {
            model_path: model_path.to_owned(),
            system: system.to_owned(),
            user: user.to_owned(),
            response,
        },
        GENERATE_TIMEOUT,
        "generating",
    )?
}

#[allow(dead_code)]
pub(crate) fn unload() -> Result<(), String> {
    LLM.send(
        |response| LlmCommand::Unload { response },
        UNLOAD_TIMEOUT,
        "unloading",
    )
}

/// The warm state owned by the single worker thread. The backend must be
/// initialised exactly once per process; the model is kept resident so repeated
/// cleanups do not reload ~1 GB of weights.
struct Warm {
    backend: LlamaBackend,
    model_path: String,
    model: LlamaModel,
}

fn run_worker(receiver: Receiver<LlmCommand>) {
    let mut warm: Option<Warm> = None;
    while let Ok(command) = receiver.recv() {
        match command {
            LlmCommand::Prepare {
                model_path,
                response,
            } => {
                let result = ensure_model(&mut warm, &model_path).map(|_| ());
                let _ = response.send(result);
            }
            LlmCommand::Generate {
                model_path,
                system,
                user,
                response,
            } => {
                // A panic inside llama.cpp would unwind through the C frame
                // (undefined behaviour) and kill the worker for the whole
                // session. Catch it, drop the possibly-corrupt model, and reply
                // with a recoverable error so cleanup simply falls back.
                let outcome = panic::catch_unwind(AssertUnwindSafe(|| {
                    let model = ensure_model(&mut warm, &model_path)?;
                    generate_once(&model.backend, &model.model, &system, &user)
                }));
                let result = outcome.unwrap_or_else(|_| {
                    warm = None;
                    Err("the offline LLM failed during generation".to_owned())
                });
                let _ = response.send(result);
            }
            LlmCommand::Unload { response } => {
                warm = None;
                let _ = response.send(());
            }
        }
    }
}

/// Ensures the model at `model_path` is warm, loading it if necessary, and
/// returns a reference to the warm state.
fn ensure_model<'a>(warm: &'a mut Option<Warm>, model_path: &str) -> Result<&'a Warm, String> {
    let needs_load = warm
        .as_ref()
        .map(|state| state.model_path != model_path)
        .unwrap_or(true);
    if needs_load {
        if model_path.trim().is_empty() {
            return Err("embedded_llm_not_installed: no model selected".to_owned());
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

#[cfg(test)]
mod tests {
    use super::*;

    // Real end-to-end generation needs a GGUF on disk, so it is opt-in via an
    // environment variable and skipped otherwise (keeps `cargo test` hermetic).
    // Run with:
    //   SWAR_LLM_TEST_MODEL=/path/to/model.gguf \
    //   cargo test -p swar_core --features embedded-llm llm:: -- --nocapture
    #[test]
    fn generates_a_cleanup_when_a_model_is_provided() {
        let Ok(path) = std::env::var("SWAR_LLM_TEST_MODEL") else {
            eprintln!("SWAR_LLM_TEST_MODEL unset — skipping embedded LLM smoke test");
            return;
        };
        let system = "You are Swar's local dictation editor. Fix spelling, spacing, \
            and punctuation of the user's text. Repair obviously misspelled English \
            words. Do not translate. Return only the edited text.";
        let raw = "To kya hamara hingalish kanplit hogya";
        let cleaned = generate(&path, system, raw).expect("generation should succeed");
        eprintln!("RAW:     {raw}");
        eprintln!("CLEANED: {cleaned}");
        assert!(!cleaned.trim().is_empty(), "model returned empty text");
        // Drop the warm model/backend before the process exits so ggml's Metal
        // device finalizer does not assert on still-live resource sets.
        unload().expect("unload should succeed");
    }
}
