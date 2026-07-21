//! Assembles the local context handed to the on-device cleanup LLM.
//!
//! Three sources, in increasing order of sensitivity: the user's own vocabulary
//! list, their recent dictations, and the text already sitting in the field they
//! are dictating into.
//!
//! **This never leaves the machine.** The assembled string is attached only to
//! `EmbeddedLlamaEnhancer`, which talks to the local `swar_llm_server`. The BYOK
//! provider deliberately does not receive it: a cloud endpoint must never see the
//! contents of the user's documents or their dictation history.

use crate::{api::personalization, storage};

// Budgets are deliberately tight. The KV prefix cache covers the *system*
// prompt, not the user turn, so every character here is re-read by the model on
// every dictation. Measured over the 205-sentence corpus, a large block cost 62%
// more latency (275 ms to 445 ms median) and produced 15% *fewer* useful edits,
// because it diluted the model's attention on the transcript it was supposed to
// be editing. Context earns its place by being small and relevant.

/// Recent dictations handed to the model as style context.
const HISTORY_ENTRIES: u32 = 5;
/// Per-entry cap, so one long dictation cannot crowd out the other four.
const HISTORY_ENTRY_BUDGET: usize = 90;
/// Total cap for the history block.
const HISTORY_BUDGET: usize = 450;
/// Cap for the text preceding the caret. The tail is kept: the words closest to
/// the cursor say the most about what comes next.
const BEFORE_CURSOR_BUDGET: usize = 250;
/// Cap for the text following the caret. The head is kept, for the same reason.
const AFTER_CURSOR_BUDGET: usize = 120;

/// The text around the caret in the focused field, already split by the platform
/// layer. Empty for a secure field — the platform never reads one.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct CursorContext<'a> {
    pub before: &'a str,
    pub after: &'a str,
}

/// Builds the context block, or an empty string when there is nothing useful to
/// say. The caller attaches it to the local LLM request only.
pub(crate) fn build(cursor: CursorContext<'_>) -> String {
    assemble(
        &personalization::hotword_prompt(),
        &recent_dictations(),
        cursor,
    )
}

/// The pure half of `build`: applies every budget to already-fetched inputs.
///
/// Separated from the storage read so the cleanup eval can measure the real
/// budgets against representative data. Evaluating a hand-written fixture only
/// ever measured the fixture, which is how a large block shipped without the
/// regression noticing its cost.
pub(crate) fn assemble(
    vocabulary: &str,
    dictations: &[String],
    cursor: CursorContext<'_>,
) -> String {
    let mut sections: Vec<String> = Vec::new();

    if !vocabulary.trim().is_empty() {
        sections.push(format!("Known terms: {}", vocabulary.trim()));
    }

    let history = history_lines(dictations);
    if !history.is_empty() {
        sections.push(format!(
            "The speaker's recent dictations, newest first:\n{}",
            history.join("\n")
        ));
    }

    let before = tail(cursor.before.trim_start(), BEFORE_CURSOR_BUDGET);
    let after = head(cursor.after.trim_end(), AFTER_CURSOR_BUDGET);
    if !before.trim().is_empty() || !after.trim().is_empty() {
        sections.push(format!(
            "Text already in the field, with <CURSOR> where the new text goes:\n{before}<CURSOR>{after}"
        ));
    }

    if sections.is_empty() {
        return String::new();
    }
    sections.join("\n\n")
}

/// The most recent dictations, newest first, one line each and within budget.
fn history_lines(dictations: &[String]) -> Vec<String> {
    let mut used = 0usize;
    let mut lines = Vec::new();
    for entry in dictations {
        let text = entry.split_whitespace().collect::<Vec<_>>().join(" ");
        if text.is_empty() {
            continue;
        }
        let line = format!("- {}", head(&text, HISTORY_ENTRY_BUDGET));
        if used + line.len() > HISTORY_BUDGET {
            break;
        }
        used += line.len();
        lines.push(line);
    }
    lines
}

fn recent_dictations() -> Vec<String> {
    let Ok(page) = storage::load_history_page("", 0, HISTORY_ENTRIES) else {
        return Vec::new();
    };
    page.records
        .into_iter()
        .map(|entry| entry.final_text)
        .collect()
}

/// First `budget` characters, split on a character boundary so multi-byte
/// Devanagari is never cut in half.
fn head(value: &str, budget: usize) -> String {
    if value.len() <= budget {
        return value.to_owned();
    }
    let end = floor_boundary(value, budget);
    format!("{}…", &value[..end])
}

/// Last `budget` characters, split on a character boundary.
fn tail(value: &str, budget: usize) -> String {
    if value.len() <= budget {
        return value.to_owned();
    }
    let start = ceil_boundary(value, value.len() - budget);
    format!("…{}", &value[start..])
}

fn floor_boundary(value: &str, index: usize) -> usize {
    let mut index = index.min(value.len());
    while index > 0 && !value.is_char_boundary(index) {
        index -= 1;
    }
    index
}

fn ceil_boundary(value: &str, index: usize) -> usize {
    let mut index = index.min(value.len());
    while index < value.len() && !value.is_char_boundary(index) {
        index += 1;
    }
    index
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_cursor_context_contributes_no_section() {
        let block = build(CursorContext {
            before: "   ",
            after: "",
        });
        assert!(!block.contains("<CURSOR>"));
    }

    #[test]
    fn cursor_marker_sits_between_the_two_halves() {
        let block = build(CursorContext {
            before: "Hi Priyam, ",
            after: " Thanks.",
        });
        assert!(block.contains("Hi Priyam, <CURSOR> Thanks."));
    }

    #[test]
    fn long_field_keeps_the_words_nearest_the_caret() {
        let before = "x".repeat(BEFORE_CURSOR_BUDGET) + "near the caret";
        let after = "close by".to_owned() + &"y".repeat(AFTER_CURSOR_BUDGET);
        let block = build(CursorContext {
            before: &before,
            after: &after,
        });
        assert!(block.contains("near the caret<CURSOR>close by"));
        // Both halves were trimmed, so the elision marker appears on each side.
        assert!(block.contains("…"));
    }

    #[test]
    fn history_is_capped_by_entry_and_total_budget() {
        // More entries than the budget allows, each longer than the per-entry cap.
        let dictations: Vec<String> = (0..40)
            .map(|index| format!("dictation {index} ") + &"word ".repeat(60))
            .collect();
        let block = assemble("", &dictations, CursorContext::default());
        let lines: Vec<&str> = block
            .lines()
            .filter(|line| line.starts_with("- "))
            .collect();
        assert!(!lines.is_empty());
        // Every line respects the per-entry cap (plus the "- " and the ellipsis).
        for line in &lines {
            assert!(line.len() <= HISTORY_ENTRY_BUDGET + 8, "{line}");
        }
        // And the block as a whole respects the total.
        assert!(lines.iter().map(|line| line.len()).sum::<usize>() <= HISTORY_BUDGET);
    }

    #[test]
    fn multibyte_text_is_never_split_mid_character() {
        // Devanagari is three bytes per character; a naive byte slice panics.
        let before = "नमस्ते".repeat(400);
        let block = build(CursorContext {
            before: &before,
            after: "",
        });
        assert!(block.contains("<CURSOR>"));
    }
}
