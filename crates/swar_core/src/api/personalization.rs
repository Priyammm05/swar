use crate::storage;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VocabularyEntry {
    pub spoken: String,
    pub written: String,
    pub use_count: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct VoiceStyleSnapshot {
    pub sample_count: u32,
    pub average_sentence_words: f64,
    pub contraction_ratio: f64,
    pub lowercase_start_ratio: f64,
}

pub fn list_vocabulary() -> Result<Vec<VocabularyEntry>, String> {
    storage::vocabulary_entries().map(|entries| {
        entries
            .into_iter()
            .map(|entry| VocabularyEntry {
                spoken: entry.spoken,
                written: entry.written,
                use_count: entry.use_count,
            })
            .collect()
    })
}

pub fn add_vocabulary(spoken: String, written: String) -> Result<(), String> {
    validate_pair(&spoken, &written)?;
    storage::upsert_vocabulary(&spoken, &written)
}

pub fn delete_vocabulary(spoken: String) -> Result<(), String> {
    storage::remove_vocabulary(&spoken)
}

/// Learns only when the user explicitly enabled the local edit flywheel.
pub fn record_user_edit(
    original: String,
    corrected: String,
    learning_opted_in: bool,
) -> Result<bool, String> {
    if !learning_opted_in || original.trim() == corrected.trim() {
        return Ok(false);
    }
    storage::record_user_edit(&original, &corrected)?;
    Ok(true)
}

pub fn get_voice_style_profile() -> Result<VoiceStyleSnapshot, String> {
    storage::voice_profile().map(|profile| VoiceStyleSnapshot {
        sample_count: profile.sample_count,
        average_sentence_words: profile.average_sentence_words,
        contraction_ratio: profile.contraction_ratio,
        lowercase_start_ratio: profile.lowercase_start_ratio,
    })
}

/// Writes opted-in correction triples to a user-owned JSONL file. This is an
/// explicit action and never uploads data.
pub fn export_learning_examples() -> Result<String, String> {
    storage::export_learning_examples()
}

pub(crate) fn apply_vocabulary(value: &str) -> String {
    let Ok(entries) = storage::vocabulary_entries() else {
        return value.to_owned();
    };
    apply_entries(value, &entries)
}

/// Whisper initial-prompt built from the user's vocabulary (swar.md §7): a short
/// list of correctly-spelled written forms that biases the decoder toward the
/// user's proper nouns at the source. The deterministic `apply_vocabulary` pass
/// still runs afterwards. Bounded so the prompt never dominates the decode.
pub(crate) fn hotword_prompt() -> String {
    let Ok(entries) = storage::vocabulary_entries() else {
        return String::new();
    };
    build_hotword_prompt(&entries)
}

/// Max characters of vocabulary handed to whisper as a bias prompt. Small on
/// purpose: a long prompt skews decoding and can be echoed into the output.
const HOTWORD_PROMPT_BUDGET: usize = 200;

fn build_hotword_prompt(entries: &[storage::StoredVocabularyEntry]) -> String {
    // `vocabulary_entries` returns most-used first, so the budget keeps the terms
    // the user actually dictates. De-duplicate case-insensitively.
    let mut seen = std::collections::BTreeSet::new();
    let mut terms = Vec::new();
    let mut length = 0;
    for entry in entries {
        let term = entry.written.trim();
        if term.is_empty() || !seen.insert(term.to_ascii_lowercase()) {
            continue;
        }
        let added = term.len() + 2; // term + ", "
        if length + added > HOTWORD_PROMPT_BUDGET {
            break;
        }
        length += added;
        terms.push(term);
    }
    terms.join(", ")
}

fn apply_entries(value: &str, entries: &[storage::StoredVocabularyEntry]) -> String {
    value
        .split_whitespace()
        .map(|token| {
            let start = token
                .find(|character: char| !character.is_ascii_punctuation())
                .unwrap_or(token.len());
            let end = token
                .char_indices()
                .rfind(|(_, character)| !character.is_ascii_punctuation())
                .map(|(index, character)| index + character.len_utf8())
                .unwrap_or(start);
            let word = &token[start..end];
            let replacement = entries
                .iter()
                .find(|entry| entry.spoken.eq_ignore_ascii_case(word))
                .map(|entry| entry.written.as_str())
                .unwrap_or(word);
            format!("{}{}{}", &token[..start], replacement, &token[end..])
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn validate_pair(spoken: &str, written: &str) -> Result<(), String> {
    if spoken.trim().is_empty() || written.trim().is_empty() {
        return Err("vocabulary values cannot be empty".to_owned());
    }
    if spoken.len() > 128 || written.len() > 128 {
        return Err("vocabulary values must be 128 characters or fewer".to_owned());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn applies_only_learned_entries_and_keeps_punctuation() {
        let entries = vec![storage::StoredVocabularyEntry {
            spoken: "sewer".to_owned(),
            written: "Swar".to_owned(),
            use_count: 3,
        }];
        assert_eq!(
            apply_entries("hello sewer, welcome", &entries),
            "hello Swar, welcome"
        );
    }

    #[test]
    fn preserves_hindi_and_hinglish_tokens_at_utf8_boundaries() {
        let entries = vec![storage::StoredVocabularyEntry {
            spoken: "sewer".to_owned(),
            written: "Swar".to_owned(),
            use_count: 3,
        }];

        assert_eq!(
            apply_entries("नमस्ते, मैं Swar बोल रहा हूँ।", &entries),
            "नमस्ते, मैं Swar बोल रहा हूँ।"
        );
        assert_eq!(
            apply_entries("नमस्ते sewer, test kar raha hoon", &entries),
            "नमस्ते Swar, test kar raha hoon"
        );
    }

    #[test]
    fn rejects_empty_or_unbounded_vocabulary_pairs() {
        assert!(validate_pair("", "Swar").is_err());
        assert!(validate_pair("spoken", &"x".repeat(129)).is_err());
    }

    fn entry(written: &str) -> storage::StoredVocabularyEntry {
        storage::StoredVocabularyEntry {
            spoken: written.to_ascii_lowercase(),
            written: written.to_owned(),
            use_count: 1,
        }
    }

    #[test]
    fn hotword_prompt_lists_written_forms_and_dedupes() {
        let entries = vec![entry("Oynix"), entry("Niyo"), entry("oynix")];
        assert_eq!(build_hotword_prompt(&entries), "Oynix, Niyo");
    }

    #[test]
    fn hotword_prompt_is_empty_without_vocabulary() {
        assert_eq!(build_hotword_prompt(&[]), "");
    }

    #[test]
    fn hotword_prompt_respects_the_character_budget() {
        let entries = (0..100)
            .map(|index| entry(&format!("Term{index:03}")))
            .collect::<Vec<_>>();
        let prompt = build_hotword_prompt(&entries);
        assert!(prompt.len() <= HOTWORD_PROMPT_BUDGET);
        // The most-used (earliest) terms survive the budget.
        assert!(prompt.starts_with("Term000, Term001"));
    }
}
