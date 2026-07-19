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
        (" new line", " \u{e000} "),
        (" next line", " \u{e000} "),
        (" nayi line", " \u{e000} "),
        (" prashn chinh", "?"),
    ]);
    let mut value = format!(" {}", normalize_whitespace(raw));
    for (spoken, punctuation) in commands {
        value = value.replace(spoken, punctuation);
    }

    let filtered = value
        .split_whitespace()
        .filter(|word| {
            !matches!(
                word.to_ascii_lowercase().as_str(),
                "um" | "uh" | "erm" | "hmm"
            )
        })
        .collect::<Vec<_>>()
        .join(" ")
        .replace(" \u{e000} ", "\n")
        .replace("\u{e000}", "\n");
    capitalize_sentences(filtered.trim())
}

fn normalize_whitespace(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn capitalize_sentences(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut capitalize_next = true;
    for character in value.chars() {
        if capitalize_next && character.is_alphabetic() {
            result.extend(character.to_uppercase());
            capitalize_next = false;
        } else {
            result.push(character);
        }
        if matches!(character, '.' | '?' | '!' | '\n') {
            capitalize_next = true;
        }
    }
    result
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

    #[test]
    fn english_hindi_and_hinglish_remain_in_the_spoken_language() {
        assert_eq!(clean_transcript("hello question mark", "clean"), "Hello?");
        assert_eq!(clean_transcript("नमस्ते prashn chinh", "clean"), "नमस्ते?");
        assert_eq!(
            clean_transcript("haan theek hai comma kal milte hain", "clean"),
            "Haan theek hai, kal milte hain"
        );
    }

    #[test]
    fn spoken_line_break_survives_whitespace_cleanup() {
        assert_eq!(
            clean_transcript("first new line second", "clean"),
            "First\nSecond"
        );
    }
}
