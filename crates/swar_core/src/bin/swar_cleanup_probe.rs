//! Shows what the cleanup stage actually does to a dictation.
//!
//! Usage:
//!
//! ```sh
//! cargo run -p swar_core --bin swar_cleanup_probe            # embedded LLM
//! cargo run -p swar_core --bin swar_cleanup_probe -- local   # deterministic
//! ```
//!
//! With no argument it uses the embedded LLM if the weights are installed, so
//! the run reflects the state a real user is in. The helper binary is found
//! beside this one in `target/`, or via `SWAR_LLM_SERVER`.

use swar_core::api::{benchmark::run_cleanup_probe, models::embedded_llm_model_path_string};

fn main() {
    let requested = std::env::args().nth(1);
    let installed = embedded_llm_model_path_string();
    let (provider, model) = match (requested.as_deref(), installed.as_deref()) {
        (Some(name), _) if !name.eq_ignore_ascii_case("embedded-llm") => (name, ""),
        (_, Some(path)) => ("embedded-llm", path),
        // No weights on disk. Say so rather than silently probing a different
        // path than the one the question was about.
        (_, None) => {
            eprintln!(
                "no cleanup model installed; probing the deterministic editor instead. \
                 Pass a provider name to choose explicitly."
            );
            ("local", "")
        }
    };

    let report = run_cleanup_probe(provider, model);
    println!(
        "{}",
        serde_json::to_string_pretty(&report).expect("probe report serializes")
    );
}
