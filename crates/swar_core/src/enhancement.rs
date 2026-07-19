#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct EnhancementRequest<'a> {
    pub raw_transcript: &'a str,
    pub safe_clean_text: &'a str,
    pub writing_mode: &'a str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct EnhancementOutcome {
    pub text: String,
    pub routed: bool,
    pub applied: bool,
    pub validation_fallback: bool,
}

pub(crate) trait TranscriptEnhancer {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String>;
}

struct EmbeddedLocalEnhancer;

impl TranscriptEnhancer for EmbeddedLocalEnhancer {
    fn enhance(&self, request: &EnhancementRequest<'_>) -> Result<String, String> {
        // V1's provider boundary is ready for the embedded llama.cpp backend.
        // Until its model asset is installed, the local deterministic result is
        // deliberately returned unchanged; there is no cloud fallback.
        Ok(request.safe_clean_text.to_owned())
    }
}

pub(crate) fn enhance_transcript(
    raw_transcript: &str,
    safe_clean_text: &str,
    writing_mode: &str,
) -> EnhancementOutcome {
    let request = EnhancementRequest {
        raw_transcript,
        safe_clean_text,
        writing_mode,
    };
    if !should_route(&request) {
        return EnhancementOutcome {
            text: safe_clean_text.to_owned(),
            routed: false,
            applied: false,
            validation_fallback: false,
        };
    }
    run_with_provider(&request, &EmbeddedLocalEnhancer)
}

fn run_with_provider(
    request: &EnhancementRequest<'_>,
    provider: &dyn TranscriptEnhancer,
) -> EnhancementOutcome {
    let Ok(candidate) = provider.enhance(request) else {
        return fallback(request, true);
    };
    if candidate.trim().is_empty()
        || !protected_tokens_are_preserved(request.safe_clean_text, &candidate)
    {
        return fallback(request, true);
    }
    EnhancementOutcome {
        applied: candidate != request.safe_clean_text,
        text: candidate,
        routed: true,
        validation_fallback: false,
    }
}

fn fallback(request: &EnhancementRequest<'_>, validation_fallback: bool) -> EnhancementOutcome {
    EnhancementOutcome {
        text: request.safe_clean_text.to_owned(),
        routed: true,
        applied: false,
        validation_fallback,
    }
}

fn should_route(request: &EnhancementRequest<'_>) -> bool {
    if request.writing_mode.eq_ignore_ascii_case("intent") {
        return true;
    }
    let lower = request.raw_transcript.to_ascii_lowercase();
    [" i mean ", " sorry ", " rather ", " correction "]
        .iter()
        .any(|marker| format!(" {lower} ").contains(marker))
        || request.raw_transcript.split_whitespace().count() >= 32
}

fn protected_tokens_are_preserved(source: &str, candidate: &str) -> bool {
    let source_tokens = protected_tokens(source);
    let candidate_tokens = protected_tokens(candidate);
    source_tokens
        .iter()
        .all(|token| candidate_tokens.contains(token))
        && !(source.chars().all(|character| !is_devanagari(character))
            && candidate.chars().any(is_devanagari))
}

fn protected_tokens(value: &str) -> Vec<String> {
    value
        .split_whitespace()
        .map(|token| token.trim_matches(|character: char| character.is_ascii_punctuation()))
        .filter(|token| {
            token.chars().any(|character| character.is_ascii_digit())
                || token.contains('@')
                || token.contains("://")
                || token.contains('_')
                || is_code_like(token)
        })
        .map(ToOwned::to_owned)
        .collect()
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

    #[test]
    fn simple_clean_text_does_not_route_to_the_optional_provider() {
        let outcome = enhance_transcript("send the note", "Send the note", "clean");
        assert!(!outcome.routed);
        assert_eq!(outcome.text, "Send the note");
    }

    #[test]
    fn intent_mode_routes_but_local_default_is_restrained() {
        let outcome = enhance_transcript("send it", "Send it", "intent");
        assert!(outcome.routed);
        assert!(!outcome.applied);
        assert!(!outcome.validation_fallback);
    }

    #[test]
    fn validator_rejects_changed_numbers_urls_and_code_tokens() {
        let request = EnhancementRequest {
            raw_transcript: "use APIKey at https://swar.dev for 42 users",
            safe_clean_text: "Use APIKey at https://swar.dev for 42 users.",
            writing_mode: "intent",
        };
        let outcome = run_with_provider(
            &request,
            &ReplacingEnhancer("Use another key for 43 users."),
        );
        assert!(outcome.validation_fallback);
        assert_eq!(outcome.text, request.safe_clean_text);
    }

    #[test]
    fn validator_rejects_unrequested_devanagari_output() {
        let request = EnhancementRequest {
            raw_transcript: "kal bhejna",
            safe_clean_text: "Kal bhejna.",
            writing_mode: "intent",
        };
        let outcome = run_with_provider(&request, &ReplacingEnhancer("कल भेजना।"));
        assert!(outcome.validation_fallback);
    }
}
