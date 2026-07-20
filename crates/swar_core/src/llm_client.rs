//! Client for the offline cleanup helper (`swar_llm_server`).
//!
//! This module owns the child process and a line-delimited stdio conversation
//! with it. It contains NO llama.cpp dependency on purpose: the helper is a
//! separate binary so the app framework links only whisper.cpp's ggml and never
//! collides with llama.cpp's copy. A single dedicated worker thread serialises
//! every request, applies a watchdog timeout, and restarts a helper that crashes
//! or wedges, so a bad generation can only ever degrade to deterministic cleanup.
//!
//! The cleanup prompt and the protected-token validation live in
//! `enhancement.rs`; this module only turns (system, user) text into model text.

use std::{
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
        LazyLock,
    },
    thread,
    time::Duration,
};

/// Marks a protocol line on the helper's stdout. Non-protocol lines (stray logs)
/// are skipped so they can never be mistaken for a response.
const RESPONSE_SENTINEL: &str = "@@SWARLLM@@ ";

/// Warm-up may load ~2 GB of weights from disk, so it is given a wide bound.
const PREPARE_TIMEOUT: Duration = Duration::from_secs(240);
/// A warm cleanup returns in well under a second; this bound also covers the rare
/// case where the first real dictation races ahead of warm-up and pays the load.
const GENERATE_TIMEOUT: Duration = Duration::from_secs(45);

static LLM: LazyLock<LlmClient> = LazyLock::new(LlmClient::spawn);

enum Job {
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
    Shutdown {
        response: Sender<()>,
    },
}

struct LlmClient {
    commands: Sender<Job>,
}

impl LlmClient {
    fn spawn() -> Self {
        let (commands, receiver) = mpsc::channel();
        thread::Builder::new()
            .name("swar-llm-client".to_owned())
            .spawn(move || run_worker(receiver))
            .expect("the LLM client worker must start");
        Self { commands }
    }

    fn send<T>(
        &self,
        make: impl FnOnce(Sender<T>) -> Job,
        timeout: Duration,
        action: &'static str,
    ) -> Result<T, String> {
        let (response, result) = mpsc::channel();
        self.commands
            .send(make(response))
            .map_err(|_| "the offline cleanup worker is unavailable".to_owned())?;
        result.recv_timeout(timeout).map_err(|error| match error {
            RecvTimeoutError::Timeout => {
                format!("the offline cleanup helper timed out while {action}")
            }
            RecvTimeoutError::Disconnected => {
                format!("the offline cleanup helper stopped while {action}")
            }
        })
    }
}

/// Loads the model into a warm helper ahead of the first cleanup so a real
/// dictation never pays the multi-hundred-millisecond (cold: multi-second) load.
pub(crate) fn prepare(model_path: &str) -> Result<(), String> {
    LLM.send(
        |response| Job::Prepare {
            model_path: model_path.to_owned(),
            response,
        },
        PREPARE_TIMEOUT,
        "loading the model",
    )?
}

/// Cleans one transcript. Returns the model's edited text (unvalidated — the
/// caller must still run it through the protected-token validator).
pub(crate) fn generate(model_path: &str, system: &str, user: &str) -> Result<String, String> {
    LLM.send(
        |response| Job::Generate {
            model_path: model_path.to_owned(),
            system: system.to_owned(),
            user: user.to_owned(),
            response,
        },
        GENERATE_TIMEOUT,
        "generating",
    )?
}

/// Stops the helper (and frees its ~2 GB of weights) when dictation is released.
pub(crate) fn shutdown() -> Result<(), String> {
    LLM.send(
        |response| Job::Shutdown { response },
        Duration::from_secs(10),
        "shutting down",
    )
}

/// A running helper: its stdin plus a channel fed by a reader thread that
/// forwards each stdout line (`Some`) and a final `None` at EOF (child exited).
struct Helper {
    child: Child,
    stdin: ChildStdin,
    lines: Receiver<Option<String>>,
}

impl Drop for Helper {
    fn drop(&mut self) {
        // Closing stdin lets the helper exit on its own; kill is the backstop.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn run_worker(receiver: Receiver<Job>) {
    let mut helper: Option<Helper> = None;
    while let Ok(command) = receiver.recv() {
        match command {
            Job::Prepare {
                model_path,
                response,
            } => {
                let result = ensure_prepared(&mut helper, &model_path);
                let _ = response.send(result);
            }
            Job::Generate {
                model_path,
                system,
                user,
                response,
            } => {
                let result = run_generate(&mut helper, &model_path, &system, &user);
                let _ = response.send(result);
            }
            Job::Shutdown { response } => {
                helper = None; // Drop kills the child.
                let _ = response.send(());
            }
        }
    }
}

fn ensure_prepared(helper: &mut Option<Helper>, model_path: &str) -> Result<(), String> {
    if helper.is_none() {
        *helper = Some(spawn_helper()?);
    }
    let request = serde_json::json!({ "model": model_path, "prepare": true }).to_string();
    match exchange(
        helper.as_mut().expect("just spawned"),
        &request,
        PREPARE_TIMEOUT,
    ) {
        Ok(_) => Ok(()),
        Err(error) => {
            *helper = None; // Restart a wedged or dead helper next time.
            Err(error)
        }
    }
}

fn run_generate(
    helper: &mut Option<Helper>,
    model_path: &str,
    system: &str,
    user: &str,
) -> Result<String, String> {
    if helper.is_none() {
        *helper = Some(spawn_helper()?);
    }
    let request =
        serde_json::json!({ "model": model_path, "system": system, "user": user }).to_string();
    match exchange(
        helper.as_mut().expect("just spawned"),
        &request,
        GENERATE_TIMEOUT,
    ) {
        Ok(text) => Ok(text),
        Err(error) => {
            *helper = None; // A crashed/timed-out helper is replaced next call.
            Err(error)
        }
    }
}

/// Writes one request line and waits for one sentinel-prefixed response line,
/// skipping any non-protocol output. Returns the response text (empty for a
/// prepare/ready reply). On timeout or EOF the caller drops the helper.
fn exchange(helper: &mut Helper, request: &str, timeout: Duration) -> Result<String, String> {
    helper
        .stdin
        .write_all(format!("{request}\n").as_bytes())
        .and_then(|_| helper.stdin.flush())
        .map_err(|_| "could not send to the offline cleanup helper".to_owned())?;
    loop {
        match helper.lines.recv_timeout(timeout) {
            Ok(Some(line)) => {
                let Some(payload) = line.strip_prefix(RESPONSE_SENTINEL) else {
                    continue; // Stray log line — ignore.
                };
                return parse_response(payload);
            }
            Ok(None) | Err(RecvTimeoutError::Disconnected) => {
                return Err("the offline cleanup helper exited".to_owned());
            }
            Err(RecvTimeoutError::Timeout) => {
                return Err("the offline cleanup helper timed out".to_owned());
            }
        }
    }
}

fn parse_response(payload: &str) -> Result<String, String> {
    let value: serde_json::Value =
        serde_json::from_str(payload).map_err(|_| "the helper returned invalid JSON".to_owned())?;
    if value["ok"].as_bool() != Some(true) {
        let message = value["error"]
            .as_str()
            .unwrap_or("the offline cleanup helper failed");
        return Err(message.to_owned());
    }
    if value["ready"].as_bool() == Some(true) {
        return Ok(String::new());
    }
    value["text"]
        .as_str()
        .map(ToOwned::to_owned)
        .ok_or_else(|| "the helper returned no text".to_owned())
}

fn spawn_helper() -> Result<Helper, String> {
    let path =
        helper_path().ok_or_else(|| "the offline cleanup helper is not installed".to_owned())?;
    let mut child = Command::new(&path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("could not start the offline cleanup helper: {error}"))?;
    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| "helper stdin unavailable".to_owned())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "helper stdout unavailable".to_owned())?;
    let (line_tx, lines) = mpsc::channel();
    thread::Builder::new()
        .name("swar-llm-reader".to_owned())
        .spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(line) => {
                        if line_tx.send(Some(line)).is_err() {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }
            let _ = line_tx.send(None); // Signal EOF (child exited).
        })
        .map_err(|error| format!("could not start the helper reader: {error}"))?;
    Ok(Helper {
        child,
        stdin,
        lines,
    })
}

/// Locates the helper binary: an explicit override for tests/dev, then the
/// bundled copy beside the app (`Contents/Resources/swar_llm_server`), then a
/// sibling of the current executable (cargo `target/` layout).
fn helper_path() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("SWAR_LLM_SERVER") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Some(path);
        }
    }
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    let bundled = dir.join("../Resources/swar_llm_server");
    if bundled.exists() {
        return Some(bundled);
    }
    let sibling = dir.join("swar_llm_server");
    if sibling.exists() {
        return Some(sibling);
    }
    None
}
