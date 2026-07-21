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
    let mut characters = value.chars().peekable();
    while let Some(character) = characters.next() {
        if capitalize_next && character.is_alphabetic() {
            result.extend(character.to_uppercase());
            capitalize_next = false;
        } else {
            result.push(character);
        }
        if matches!(character, '.' | '?' | '!' | '\n') {
            // A full stop only ends a sentence when something separates it from
            // the next word. Without that check this rewrote "hello@swar.dev"
            // as "hello@swar.Dev", and did the same to every domain, file name,
            // and version number a person dictated.
            capitalize_next =
                character == '\n' || characters.peek().is_none_or(char::is_ascii_whitespace);
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
    fn a_dot_inside_a_word_does_not_start_a_sentence() {
        assert_eq!(
            clean_transcript("email hello@swar.dev to me", "clean"),
            "Email hello@swar.dev to me"
        );
        assert_eq!(
            clean_transcript("open notes.txt then close it", "clean"),
            "Open notes.txt then close it"
        );
        // A real sentence boundary must still capitalise.
        assert_eq!(
            clean_transcript("that is done full stop next one starts", "clean"),
            "That is done. Next one starts"
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
