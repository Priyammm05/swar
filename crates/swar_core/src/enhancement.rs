use std::{collections::BTreeMap, time::Duration};

pub(crate) const VALIDATION_ERROR_CODE: &str = "swar-INTENT-004";

// Bounds the optional BYOK request so a slow or half-open provider can never
// hang the dictation pipeline (and the reserved coordinator) in `Enhancing`.
const PROVIDER_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const PROVIDER_IO_TIMEOUT: Duration = Duration::from_secs(30);
const CLEANUP_PROMPT: &str = include_str!("../../../models/prompts/cleanup-v1.txt");

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct EnhancementRequest<'a> {
    pub raw_transcript: &'a str,
    pub safe_clean_text: &'a str,
    pub writing_mode: &'a str,
    pub source_application: &'a str,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct EnhancementProviderConfig<'a> {
    pub provider: &'a str,
    pub endpoint: &'a str,
    pub model: &'a str,
    pub api_key: &'a str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct EnhancementOutcome {
    pub text: String,
    pub routed: bool,
    pub applied: bool,
    pub validation_fallback: bool,
    pub error_code: Option<&'static str>,
}

pub(crate) trait TranscriptEnhancer {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String>;
}

/// Embedded deterministic editor used on every supported machine. The
/// llama.cpp provider can replace this implementation through the same narrow
/// trait after its model pack passes the licence and benchmark gates.
struct EmbeddedLocalEnhancer;

struct OpenAiCompatibleEnhancer<'a> {
    config: EnhancementProviderConfig<'a>,
}

/// The offline cleanup enhancer. It sends the text to the out-of-process helper
/// (`swar_llm_server`) via `llm_client`, using `config.model` as the GGUF path.
/// When the helper or model is absent the client returns an error and the caller
/// falls back to the deterministic editor, so this is always safe to select.
struct EmbeddedLlamaEnhancer<'a> {
    config: EnhancementProviderConfig<'a>,
}

/// The cleanup system prompt. Deliberately constant: the helper keeps a decoded
/// KV-cache prefix of the system turn and only re-decodes it when the text
/// changes, which removes the whole prompt from the per-dictation cost. Anything
/// that varies per request (the target application) belongs in the user turn.
pub(crate) fn cleanup_system_prompt() -> &'static str {
    CLEANUP_PROMPT
}

/// The user turn: the transcript, plus the target-application context when it is
/// known. Shared by every LLM backend so their instructions are identical.
fn cleanup_user_message(source_application: &str, safe_clean_text: &str) -> String {
    let application = source_application.trim();
    if application.is_empty() {
        safe_clean_text.to_owned()
    } else {
        format!(
            "The text will be inserted into {application}. Preserve its register without adding information.\n\n{safe_clean_text}"
        )
    }
}

impl TranscriptEnhancer for EmbeddedLlamaEnhancer<'_> {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String> {
        let model_path = self.config.model.trim();
        if model_path.is_empty() {
            return Err("no embedded LLM model is installed".to_owned());
        }
        let user = cleanup_user_message(request.source_application, request.safe_clean_text);
        crate::llm_client::generate(model_path, cleanup_system_prompt(), &user)
    }
}

impl TranscriptEnhancer for EmbeddedLocalEnhancer {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String> {
        let mut value = resolve_clear_correction(request.safe_clean_text);
        if request
            .raw_transcript
            .to_ascii_lowercase()
            .contains("make this an email")
        {
            value = value
                .replace("Make this an email", "")
                .replace("make this an email", "")
                .trim()
                .to_owned();
        }
        if request
            .source_application
            .to_ascii_lowercase()
            .contains("mail")
            && !value.ends_with(['.', '?', '!'])
        {
            value.push('.');
        }
        Ok(value)
    }
}

impl TranscriptEnhancer for OpenAiCompatibleEnhancer<'_> {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String> {
        let endpoint = self.config.endpoint.trim().trim_end_matches('/');
        let is_localhost =
            endpoint.starts_with("http://127.0.0.1") || endpoint.starts_with("http://localhost");
        if !endpoint.starts_with("https://") && !is_localhost {
            return Err("the provider endpoint must use HTTPS or localhost".to_owned());
        }
        let api_key = self.config.api_key.trim();
        // A local LLM server (Ollama, llama-server) needs no key; a remote HTTPS
        // provider still does. Only the key requirement is relaxed for localhost.
        if api_key.is_empty() && !is_localhost {
            return Err("the provider API key is unavailable".to_owned());
        }
        let url = if endpoint.ends_with("/chat/completions") {
            endpoint.to_owned()
        } else {
            format!("{endpoint}/chat/completions")
        };
        let body = serde_json::json!({
            "model": self.config.model,
            "temperature": 0,
            "messages": [
                {"role": "system", "content": cleanup_system_prompt()},
                {"role": "user", "content": cleanup_user_message(request.source_application, request.safe_clean_text)}
            ]
        });
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(PROVIDER_CONNECT_TIMEOUT)
            .timeout_read(PROVIDER_IO_TIMEOUT)
            .timeout_write(PROVIDER_IO_TIMEOUT)
            .build();
        let mut post = agent.post(&url).set("Content-Type", "application/json");
        if !api_key.is_empty() {
            post = post.set("Authorization", &format!("Bearer {api_key}"));
        }
        let response = post
            .send_json(body)
            .map_err(|_| "the optional provider request failed".to_owned())?;
        let value: serde_json::Value = response
            .into_json()
            .map_err(|_| "the optional provider returned invalid JSON".to_owned())?;
        value["choices"][0]["message"]["content"]
            .as_str()
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(ToOwned::to_owned)
            .ok_or_else(|| "the optional provider returned no text".to_owned())
    }
}

pub(crate) fn enhance_transcript(
    raw_transcript: &str,
    safe_clean_text: &str,
    writing_mode: &str,
    source_application: &str,
    provider_config: EnhancementProviderConfig<'_>,
) -> EnhancementOutcome {
    let request = EnhancementRequest {
        raw_transcript,
        safe_clean_text,
        writing_mode,
        source_application,
    };
    let provider = provider_config.provider;
    let is_byok = provider.eq_ignore_ascii_case("byok");
    let is_local_llm = provider.eq_ignore_ascii_case("local-llm");
    let is_embedded_llm = provider.eq_ignore_ascii_case("embedded-llm");
    // A local or embedded LLM is free and offline, so — like Wispr — it cleans up
    // every non-trivial dictation, not only ones with explicit correction cues.
    // Remote BYOK and the deterministic editor keep the conservative gate.
    let liberal = (is_local_llm || is_embedded_llm) && has_cleanable_content(&request);
    let route = should_route(&request) || liberal;
    if !route {
        return EnhancementOutcome {
            text: safe_clean_text.to_owned(),
            routed: false,
            applied: false,
            validation_fallback: false,
            error_code: None,
        };
    }
    if is_byok || is_local_llm {
        run_with_provider(
            &request,
            &OpenAiCompatibleEnhancer {
                config: provider_config,
            },
        )
    } else if is_embedded_llm {
        run_embedded_llm(&request, provider_config)
    } else {
        run_with_provider(&request, &EmbeddedLocalEnhancer)
    }
}

/// Routes to the offline cleanup helper. When the helper or model is missing the
/// client errors and `run_with_provider` falls back to the deterministic editor,
/// so this always produces safe text regardless of install state.
fn run_embedded_llm(
    request: &EnhancementRequest<'_>,
    config: EnhancementProviderConfig<'_>,
) -> EnhancementOutcome {
    run_with_provider(request, &EmbeddedLlamaEnhancer { config })
}

/// Enough words to be worth an LLM pass. Skips a single-word snippet so the LLM
/// does not add latency to a one-word dictation, but a two-word phrase like
/// "mic testing" is cleaned — that is exactly the homophone case the LLM exists
/// to fix, so it must not be gated out.
fn has_cleanable_content(request: &EnhancementRequest<'_>) -> bool {
    request.raw_transcript.split_whitespace().count() >= 2
}

fn run_with_provider(
    request: &EnhancementRequest<'_>,
    provider: &dyn TranscriptEnhancer,
) -> EnhancementOutcome {
    let Ok(candidate) = provider.enhance(request) else {
        return fallback(request, true);
    };
    let validation_source = resolve_clear_correction(request.safe_clean_text);
    if candidate.trim().is_empty()
        || !protected_tokens_are_preserved(&validation_source, &candidate)
    {
        return fallback(request, true);
    }
    EnhancementOutcome {
        applied: candidate != request.safe_clean_text,
        text: candidate,
        routed: true,
        validation_fallback: false,
        error_code: None,
    }
}

fn fallback(request: &EnhancementRequest<'_>, validation_fallback: bool) -> EnhancementOutcome {
    EnhancementOutcome {
        text: request.safe_clean_text.to_owned(),
        routed: true,
        applied: false,
        validation_fallback,
        error_code: validation_fallback.then_some(VALIDATION_ERROR_CODE),
    }
}

fn should_route(request: &EnhancementRequest<'_>) -> bool {
    if request.writing_mode.eq_ignore_ascii_case("intent") {
        return true;
    }
    let padded = format!(" {} ", request.raw_transcript.to_ascii_lowercase());
    [
        " i mean ",
        " scratch that ",
        " no wait ",
        " nahi nahi ",
        " matlab i mean ",
        " correction ",
        " make this an email ",
        " first ",
        " secondly ",
    ]
    .iter()
    .any(|marker| padded.contains(marker))
        || contains_clear_sorry_correction(request.safe_clean_text)
        || request.raw_transcript.matches([',', '.', '?', '!']).count() >= 2
        || request.raw_transcript.split_whitespace().count() >= 32
}

fn resolve_clear_correction(value: &str) -> String {
    for cue in [
        "scratch that",
        "no wait",
        "nahi nahi",
        "matlab i mean",
        "i mean",
    ] {
        if let Some(result) = replace_corrected_suffix(value, cue, false) {
            return result;
        }
    }
    if contains_clear_sorry_correction(value) {
        if let Some(result) = replace_corrected_suffix(value, "sorry", true) {
            return result;
        }
    }
    value.to_owned()
}

fn replace_corrected_suffix(value: &str, cue: &str, require_pair: bool) -> Option<String> {
    let lower = value.to_ascii_lowercase();
    let index = lower.find(&format!(" {cue} "))?;
    let before = value[..index].trim_end_matches([' ', ',', '.', ';']);
    let after = value[index + cue.len() + 2..].trim_start_matches([' ', ',', '.', ';']);
    let before_words = before.split_whitespace().collect::<Vec<_>>();
    let after_words = after.split_whitespace().collect::<Vec<_>>();
    let first_after = normalized_word(after_words.first()?);
    let last_before = normalized_word(before_words.last()?);
    if require_pair && !is_correction_pair(last_before, first_after) {
        return None;
    }
    let correction_words = correction_phrase_length(&after_words);
    let remove_count = correction_words.min(before_words.len()).max(1);
    let prefix = before_words[..before_words.len() - remove_count].join(" ");
    let joined = if prefix.is_empty() {
        after.to_owned()
    } else {
        format!("{prefix} {after}")
    };
    Some(capitalize_first(joined.trim()))
}

fn correction_phrase_length(words: &[&str]) -> usize {
    let count = words
        .iter()
        .take_while(|word| is_number_word(normalized_word(word)))
        .count();
    count.max(1)
}

fn contains_clear_sorry_correction(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    let Some(index) = lower.find(" sorry ") else {
        return false;
    };
    let before = value[..index].split_whitespace().last();
    let after = value[index + 7..].split_whitespace().next();
    before.zip(after).is_some_and(|(left, right)| {
        is_correction_pair(normalized_word(left), normalized_word(right))
    })
}

fn is_correction_pair(left: &str, right: &str) -> bool {
    (is_number_word(left) && is_number_word(right))
        || (is_date_or_time_word(left) && is_date_or_time_word(right))
}

fn is_number_word(value: &str) -> bool {
    value.chars().any(|value| value.is_ascii_digit())
        || matches!(
            value,
            "zero"
                | "one"
                | "two"
                | "three"
                | "four"
                | "five"
                | "six"
                | "seven"
                | "eight"
                | "nine"
                | "ten"
                | "hundred"
                | "thousand"
                | "lakh"
                | "crore"
        )
}

fn is_date_or_time_word(value: &str) -> bool {
    matches!(
        value,
        "today"
            | "tomorrow"
            | "yesterday"
            | "aaj"
            | "kal"
            | "monday"
            | "tuesday"
            | "wednesday"
            | "thursday"
            | "friday"
            | "saturday"
            | "sunday"
            | "january"
            | "february"
            | "march"
            | "april"
            | "may"
            | "june"
            | "july"
            | "august"
            | "september"
            | "october"
            | "november"
            | "december"
    ) || value.contains(':')
}

fn protected_tokens_are_preserved(source: &str, candidate: &str) -> bool {
    protected_tokens(source) == protected_tokens(candidate)
        && language_signature(source) == language_signature(candidate)
        && !(source.chars().all(|character| !is_devanagari(character))
            && candidate.chars().any(is_devanagari))
}

fn protected_tokens(value: &str) -> BTreeMap<String, usize> {
    let mut result = BTreeMap::new();
    for (index, token) in value.split_whitespace().enumerate() {
        let normalized = normalized_word(token).to_ascii_lowercase();
        if normalized.is_empty() || is_unprotected_structure_word(&normalized) {
            continue;
        }
        let protected = normalized
            .chars()
            .any(|character| character.is_ascii_digit())
            || normalized.contains('@')
            || normalized.contains("http")
            || normalized.contains('/')
            || normalized.contains('\\')
            || normalized.contains('_')
            || normalized
                .chars()
                .next()
                .is_some_and(|value| matches!(value, '₹' | '$' | '€' | '£'))
            || is_code_like(normalized_word(token))
            || is_number_word(&normalized)
            || is_date_or_time_word(&normalized)
            || is_negation(&normalized)
            || is_hinglish_marker(&normalized)
            || (index > 0 && token.chars().next().is_some_and(char::is_uppercase));
        if protected {
            *result.entry(normalized).or_insert(0) += 1;
        }
    }
    result
}

fn language_signature(value: &str) -> (usize, usize) {
    value
        .split_whitespace()
        .fold((0, 0), |(roman, devanagari), token| {
            (
                roman + usize::from(is_hinglish_marker(normalized_word(token))),
                devanagari + usize::from(token.chars().any(is_devanagari)),
            )
        })
}

fn is_unprotected_structure_word(value: &str) -> bool {
    matches!(
        value,
        "a" | "an"
            | "the"
            | "and"
            | "or"
            | "but"
            | "to"
            | "for"
            | "of"
            | "in"
            | "on"
            | "at"
            | "is"
            | "are"
            | "was"
            | "were"
            | "be"
            | "this"
            | "that"
            | "it"
            | "i"
            | "we"
            | "you"
            | "he"
            | "she"
            | "they"
            | "make"
            | "email"
            | "please"
    )
}

fn is_negation(value: &str) -> bool {
    matches!(
        value,
        "no" | "not" | "never" | "don't" | "cant" | "can't" | "nahi" | "mat"
    )
}

fn is_hinglish_marker(value: &str) -> bool {
    matches!(
        value,
        "hai"
            | "hain"
            | "haan"
            | "nahi"
            | "kya"
            | "karo"
            | "karna"
            | "kar"
            | "kal"
            | "aaj"
            | "bhai"
            | "bhej"
            | "dena"
            | "wala"
            | "wali"
            | "phir"
            | "mujhe"
            | "ko"
            | "ke"
            | "ki"
            | "ka"
            | "se"
            | "tak"
            | "theek"
            | "milte"
    )
}

fn is_code_like(token: &str) -> bool {
    let has_lower = token
        .chars()
        .any(|character| character.is_ascii_lowercase());
    let has_upper = token
        .chars()
        .any(|character| character.is_ascii_uppercase());
    (has_lower && has_upper) || (token.len() > 1 && token.chars().all(|c| c.is_ascii_uppercase()))
}

fn normalized_word(value: &str) -> &str {
    value.trim_matches(|character: char| {
        character.is_ascii_punctuation() && !matches!(character, '@' | '/' | '\\' | '_' | ':' | '.')
    })
}

fn capitalize_first(value: &str) -> String {
    let mut characters = value.chars();
    let Some(first) = characters.next() else {
        return String::new();
    };
    first.to_uppercase().collect::<String>() + characters.as_str()
}

fn is_devanagari(character: char) -> bool {
    ('\u{0900}'..='\u{097f}').contains(&character)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct ReplacingEnhancer(&'static str);

    impl TranscriptEnhancer for ReplacingEnhancer {
        fn enhance(&self, _request: &EnhancementRequest<'_>) -> Result<String, String> {
            Ok(self.0.to_owned())
        }
    }

    fn request<'a>(source: &'a str) -> EnhancementRequest<'a> {
        EnhancementRequest {
            raw_transcript: source,
            safe_clean_text: source,
            writing_mode: "intent",
            source_application: "",
        }
    }

    #[test]
    fn simple_clean_text_does_not_route_to_the_optional_provider() {
        let outcome = enhance_transcript(
            "send the note",
            "Send the note",
            "clean",
            "",
            local_provider(),
        );
        assert!(!outcome.routed);
        assert_eq!(outcome.text, "Send the note");
    }

    #[test]
    fn clear_correction_keeps_the_final_choice() {
        let outcome = enhance_transcript(
            "meet on Tuesday scratch that Wednesday",
            "Meet on Tuesday scratch that Wednesday",
            "clean",
            "Calendar",
            local_provider(),
        );
        assert!(outcome.applied);
        assert_eq!(outcome.text, "Meet on Wednesday");
    }

    #[test]
    fn sorry_as_an_apology_is_not_treated_as_a_correction() {
        let source = "Sorry I missed your call";
        let outcome = enhance_transcript(source, source, "clean", "", local_provider());
        assert!(!outcome.routed);
        assert_eq!(outcome.text, source);
    }

    #[test]
    fn validator_rejects_changed_protected_values_with_stable_error_code() {
        let request = request("Use APIKey at https://swar.dev for 42 users");
        let outcome =
            run_with_provider(&request, &ReplacingEnhancer("Use another key for 43 users"));
        assert!(outcome.validation_fallback);
        assert_eq!(outcome.error_code, Some(VALIDATION_ERROR_CODE));
    }

    #[test]
    fn validator_rejects_negation_names_and_language_changes() {
        for candidate in [
            "Send ₹1,000 to someone",
            "Send ₹1,000 to Ramesh",
            "कल Ramesh ko ₹1,000 mat bhejna",
        ] {
            let request = request("Kal Ramesh ko ₹1,000 nahi bhejna");
            assert!(run_with_provider(&request, &ReplacingEnhancer(candidate)).validation_fallback);
        }
    }

    #[test]
    fn restraint_keeps_actually_when_it_is_not_a_correction() {
        let source = "I actually enjoyed the movie";
        let outcome = enhance_transcript(source, source, "intent", "", local_provider());
        assert_eq!(outcome.text, source);
        assert!(!outcome.validation_fallback);
    }

    fn local_provider() -> EnhancementProviderConfig<'static> {
        EnhancementProviderConfig {
            provider: "local",
            endpoint: "",
            model: "",
            api_key: "",
        }
    }

    fn local_llm_provider(endpoint: &'static str) -> EnhancementProviderConfig<'static> {
        EnhancementProviderConfig {
            provider: "local-llm",
            endpoint,
            model: "qwen2.5:3b",
            api_key: "",
        }
    }

    #[test]
    fn local_llm_routes_plain_text_that_the_conservative_gate_would_skip() {
        // "send the note" has no correction cue, so the embedded editor leaves it
        // un-routed; a local LLM should still take it (Wispr-style always-clean).
        let outcome = enhance_transcript(
            "send the note now",
            "Send the note now",
            "clean",
            "",
            // Unreachable endpoint → provider errors → safe fallback, but the key
            // signal is that it *routed*.
            local_llm_provider("http://127.0.0.1:59999/v1"),
        );
        assert!(outcome.routed, "local LLM must clean plain dictation");
        assert_eq!(outcome.text, "Send the note now");
    }

    #[test]
    fn local_llm_skips_a_trivial_single_word_snippet() {
        let outcome = enhance_transcript(
            "okay",
            "Okay",
            "clean",
            "",
            local_llm_provider("http://127.0.0.1:59999/v1"),
        );
        assert!(!outcome.routed);
        assert_eq!(outcome.text, "Okay");
    }

    #[test]
    fn local_llm_cleans_a_two_word_homophone_phrase() {
        // "mic testing" is two words: it must reach the LLM (route), not be gated
        // out as trivial. No server is listening, so it routes and then falls back
        // to safe text — the assertion is that it *routed*.
        let outcome = enhance_transcript(
            "mic testing",
            "Mic testing",
            "clean",
            "",
            local_llm_provider("http://127.0.0.1:59999/v1"),
        );
        assert!(outcome.routed, "a two-word phrase must reach the LLM");
    }

    #[test]
    fn localhost_endpoint_is_accepted_without_an_api_key() {
        let enhancer = OpenAiCompatibleEnhancer {
            config: local_llm_provider("http://localhost:11434/v1"),
        };
        // No server is listening, so this errors on the request — but it must get
        // past the key/endpoint guards (i.e. not the "API key unavailable" error).
        let error = enhancer
            .enhance(&request("clean this up please"))
            .unwrap_err();
        assert!(!error.contains("API key"), "localhost must not need a key");
    }

    #[test]
    fn remote_http_endpoint_still_requires_a_key() {
        let enhancer = OpenAiCompatibleEnhancer {
            config: EnhancementProviderConfig {
                provider: "local-llm",
                endpoint: "http://example.test/v1",
                model: "x",
                api_key: "",
            },
        };
        let error = enhancer
            .enhance(&request("clean this up please"))
            .unwrap_err();
        assert!(error.contains("HTTPS or localhost"));
    }
}
