use std::collections::HashMap;

pub(crate) fn clean_transcript(raw: &str, writing_mode: &str) -> String {
    if writing_mode.eq_ignore_ascii_case("raw") {
        return normalize_whitespace(raw);
    }

    let commands = HashMap::from([
        (" comma", ","),
        (" full stop", "."),
        (" period", "."),
        (" question mark", "?"),
        (" new line", "\n"),
    ]);
    let mut value = format!(" {}", normalize_whitespace(raw));
    for (spoken, punctuation) in commands {
        value = value.replace(spoken, punctuation);
    }

    let filtered = value
        .split_whitespace()
        .filter(|word| !matches!(word.to_ascii_lowercase().as_str(), "um" | "uh" | "erm"))
        .collect::<Vec<_>>()
        .join(" ");
    capitalize_sentence_start(filtered.trim())
}

fn normalize_whitespace(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn capitalize_sentence_start(value: &str) -> String {
    let mut characters = value.chars();
    let Some(first) = characters.next() else {
        return String::new();
    };
    first.to_uppercase().collect::<String>() + characters.as_str()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_mode_removes_fillers_and_applies_spoken_punctuation() {
        assert_eq!(
            clean_transcript("um please review this comma thanks full stop", "clean"),
            "Please review this, thanks."
        );
    }

    #[test]
    fn raw_mode_preserves_words_and_only_repairs_spacing() {
        assert_eq!(
            clean_transcript("  um   keep this  ", "raw"),
            "um keep this"
        );
    }
}
