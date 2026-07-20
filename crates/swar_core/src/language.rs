//! Offline language post-processing for dictation output.
//!
//! Whisper returns Hindi in Devanagari (`कल क्या होगा?`). For Hinglish and Auto
//! modes Swar must present Hindi in Roman script (`Kal kya hoga?`) while leaving
//! English, technical terms, numbers, URLs, emails and code untouched. This is
//! transliteration (script change), never translation.
//!
//! The pipeline here is deterministic and fully offline:
//!   raw transcript
//!     -> split into Devanagari vs non-Devanagari runs (script detection)
//!     -> transliterate only the Devanagari runs to Roman
//!     -> leave every other run (Latin words, numbers, URLs, code) verbatim
//!
//! A rule-based transliterator is good, not perfect — notably it keeps some
//! medial schwas ("kitane" rather than "kitne"). A neural transliterator can be
//! swapped in later behind [`to_output_script`] without touching callers.

/// Whether a mode's final output should be Roman script (Hindi transliterated)
/// or left in whatever script Whisper produced.
///
/// - `hinglish` / `automatic` → Roman (transliterate Devanagari spans)
/// - `hindi` → Devanagari (leave as decoded)
/// - `english` / anything else → leave as decoded
fn output_is_roman(mode: &str) -> bool {
    matches!(
        mode.trim().to_ascii_lowercase().as_str(),
        "hinglish" | "automatic"
    )
}

/// Convert a raw transcript to the script required by `mode`. Non-Roman modes
/// return the input unchanged; Roman modes transliterate only the Devanagari
/// spans and preserve every other character exactly (spacing included).
pub(crate) fn to_output_script(raw: &str, mode: &str) -> String {
    if output_is_roman(mode) {
        transliterate_mixed(raw)
    } else {
        raw.to_owned()
    }
}

/// Devanagari block (U+0900–U+097F) plus the Extended block (U+A8E0–U+A8FF).
/// Only these code points are transliterated; everything else is preserved.
fn is_devanagari(c: char) -> bool {
    ('\u{0900}'..='\u{097F}').contains(&c) || ('\u{A8E0}'..='\u{A8FF}').contains(&c)
}

/// Split into maximal Devanagari / non-Devanagari runs, transliterating only the
/// Devanagari runs. Latin words, numbers, whitespace, punctuation, URLs, emails
/// and code sit in non-Devanagari runs and pass through untouched — that is how
/// protected tokens are preserved without a separate allow-list.
fn transliterate_mixed(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut run = String::new();
    let mut run_is_devanagari = false;

    for c in raw.chars() {
        let dev = is_devanagari(c);
        if run.is_empty() {
            run_is_devanagari = dev;
            run.push(c);
            continue;
        }
        if dev == run_is_devanagari {
            run.push(c);
            continue;
        }
        flush_run(&mut out, &run, run_is_devanagari);
        run.clear();
        run_is_devanagari = dev;
        run.push(c);
    }
    flush_run(&mut out, &run, run_is_devanagari);
    out
}

fn flush_run(out: &mut String, run: &str, is_devanagari: bool) {
    if run.is_empty() {
        return;
    }
    if is_devanagari {
        out.push_str(&romanize_run(run));
    } else {
        out.push_str(run);
    }
}

/// One romanized unit: a consonant/nasal (`is_vowel = false`) or a vowel. An
/// `inherent` vowel is the implicit "a" that follows a bare consonant and is the
/// only kind eligible for schwa deletion.
struct Unit {
    text: &'static str,
    is_vowel: bool,
    inherent: bool,
}

impl Unit {
    fn consonant(text: &'static str) -> Self {
        Unit {
            text,
            is_vowel: false,
            inherent: false,
        }
    }
    fn vowel(text: &'static str) -> Self {
        Unit {
            text,
            is_vowel: true,
            inherent: false,
        }
    }
    fn inherent_schwa() -> Self {
        Unit {
            text: "a",
            is_vowel: true,
            inherent: true,
        }
    }
}

/// Transliterate a run that is entirely Devanagari. Because inter-word spaces are
/// non-Devanagari, a run is a single orthographic word. The run is first parsed
/// into romanized units (each bare consonant contributing an inherent schwa),
/// then Hindi schwa deletion is applied before the units are concatenated.
#[allow(unused_assignments)] // `settle!` clears the schwa debt on its last use.
fn romanize_run(run: &str) -> String {
    let mut units: Vec<Unit> = Vec::new();
    // Whether the previous consonant still owes its inherent schwa (no matra or
    // virama has resolved it yet).
    let mut owes_schwa = false;
    let chars: Vec<char> = run.chars().collect();
    let mut i = 0;

    macro_rules! settle {
        () => {
            if owes_schwa {
                units.push(Unit::inherent_schwa());
                owes_schwa = false;
            }
        };
    }

    while i < chars.len() {
        let c = chars[i];

        // Standalone combining nukta: retro-modify the last consonant (ज + ़ → z).
        if c == '\u{093C}' {
            if let Some(last) = units.last_mut() {
                if !last.is_vowel {
                    last.text = nukta_remap(last.text);
                }
            }
            i += 1;
            continue;
        }

        if let Some(mut base) = consonant(c) {
            if i + 1 < chars.len() && chars[i + 1] == '\u{093C}' {
                base = nukta_remap(base);
                i += 1;
            }
            settle!();
            units.push(Unit::consonant(base));
            owes_schwa = true;
            i += 1;
            continue;
        }

        if let Some(m) = matra(c) {
            // The matra is this consonant's vowel, so no inherent schwa.
            owes_schwa = false;
            units.push(Unit::vowel(m));
            i += 1;
            continue;
        }

        // Virama: the consonant has no vowel at all (a conjunct cluster).
        if c == '\u{094D}' {
            owes_schwa = false;
            i += 1;
            continue;
        }

        if let Some(v) = vowel(c) {
            settle!();
            units.push(Unit::vowel(v));
            i += 1;
            continue;
        }

        // Anusvara / chandrabindu → nasal; visarga → h.
        if c == '\u{0902}' || c == '\u{0901}' {
            settle!();
            units.push(Unit::consonant("n"));
            i += 1;
            continue;
        }
        if c == '\u{0903}' {
            settle!();
            units.push(Unit::consonant("h"));
            i += 1;
            continue;
        }

        if let Some(d) = devanagari_digit(c) {
            settle!();
            units.push(Unit::consonant(d));
            i += 1;
            continue;
        }

        if c == '\u{0950}' {
            settle!();
            units.push(Unit::consonant("om"));
            i += 1;
            continue;
        }

        // Danda, avagraha, stray combining accents: settle any owed schwa and
        // drop the mark (sentence punctuation is re-applied by cleanup).
        settle!();
        i += 1;
    }
    settle!();

    delete_schwas(&mut units);

    units
        .iter()
        .filter(|unit| !unit.dropped())
        .map(|unit| unit.text)
        .collect()
}

impl Unit {
    fn dropped(&self) -> bool {
        self.text.is_empty()
    }
}

/// Apply Hindi schwa deletion in place (deleted units are blanked).
///
/// - Word-final inherent schwa is deleted unless it is the word's only vowel, so
///   कल → "kal" but क stays "ka".
/// - A medial inherent schwa is deleted in the classic `V C _ C V` context
///   (preceded by vowel+consonant, followed by consonant+vowel), so करना → "karna"
///   and कितने → "kitne", while नमस्ते stays "namaste" (the following स्त is a
///   cluster, not C+V).
///
/// Deletion runs right-to-left so an already-deleted final schwa no longer counts
/// as the "V" of a preceding context (स्वागत → "svagat", not "svagt").
fn delete_schwas(units: &mut [Unit]) {
    let vowel_count = units.iter().filter(|u| u.is_vowel).count();
    let is_consonant = |u: &Unit| !u.is_vowel && !u.dropped();

    for j in (0..units.len()).rev() {
        if !units[j].is_vowel || !units[j].inherent {
            continue;
        }
        let next1 = (j + 1..units.len()).find(|&k| !units[k].dropped());
        let delete = match next1 {
            // Word-final schwa: delete unless it is the only vowel in the word.
            None => vowel_count > 1,
            Some(n1) => {
                let next2 = (n1 + 1..units.len()).find(|&k| !units[k].dropped());
                let left_ok = j >= 2 && is_consonant(&units[j - 1]) && units[j - 2].is_vowel;
                let right_ok =
                    is_consonant(&units[n1]) && next2.is_some_and(|n2| units[n2].is_vowel);
                left_ok && right_ok
            }
        };
        if delete {
            units[j].text = "";
        }
    }
}

fn consonant(c: char) -> Option<&'static str> {
    Some(match c {
        'क' => "k",
        'ख' => "kh",
        'ग' => "g",
        'घ' => "gh",
        'ङ' => "ng",
        'च' => "ch",
        'छ' => "chh",
        'ज' => "j",
        'झ' => "jh",
        'ञ' => "ny",
        'ट' => "t",
        'ठ' => "th",
        'ड' => "d",
        'ढ' => "dh",
        'ण' => "n",
        'त' => "t",
        'थ' => "th",
        'द' => "d",
        'ध' => "dh",
        'न' => "n",
        'प' => "p",
        'फ' => "ph",
        'ब' => "b",
        'भ' => "bh",
        'म' => "m",
        'य' => "y",
        'र' => "r",
        'ल' => "l",
        'व' => "v",
        'श' => "sh",
        'ष' => "sh",
        'स' => "s",
        'ह' => "h",
        'ळ' => "l",
        'ऱ' => "r",
        // Precomposed nukta consonants (single code points U+0958–U+095F). The
        // decomposed base+U+093C forms are handled by the combining-nukta path.
        '\u{0958}' => "q",
        '\u{0959}' => "kh",
        '\u{095A}' => "gh",
        '\u{095B}' => "z",
        '\u{095C}' => "r",
        '\u{095D}' => "rh",
        '\u{095E}' => "f",
        '\u{095F}' => "y",
        _ => return None,
    })
}

/// Remap a consonant base when a combining nukta follows.
fn nukta_remap(base: &'static str) -> &'static str {
    match base {
        "k" => "q",
        "g" => "gh",
        "j" => "z",
        "d" => "r",
        "dh" => "rh",
        "ph" => "f",
        other => other,
    }
}

/// Dependent vowel signs (matras). Long/short are folded to the casual Hinglish
/// single form (ा → "a", ी → "i", ू → "u") so output reads `hoga`, not `hogaa`.
fn matra(c: char) -> Option<&'static str> {
    Some(match c {
        'ा' => "a",
        'ि' => "i",
        'ी' => "i",
        'ु' => "u",
        'ू' => "u",
        'ृ' => "ri",
        'ॄ' => "ri",
        'ॅ' => "e",
        'े' => "e",
        'ै' => "ai",
        'ॉ' => "o",
        'ो' => "o",
        'ौ' => "au",
        _ => return None,
    })
}

/// Independent vowels.
fn vowel(c: char) -> Option<&'static str> {
    Some(match c {
        'अ' => "a",
        'आ' => "a",
        'इ' => "i",
        'ई' => "i",
        'उ' => "u",
        'ऊ' => "u",
        'ऋ' => "ri",
        'ॠ' => "ri",
        'ऎ' => "e",
        'ऍ' => "e",
        'ए' => "e",
        'ऐ' => "ai",
        'ऑ' => "o",
        'ऒ' => "o",
        'ओ' => "o",
        'औ' => "au",
        _ => return None,
    })
}

fn devanagari_digit(c: char) -> Option<&'static str> {
    Some(match c {
        '०' => "0",
        '१' => "1",
        '२' => "2",
        '३' => "3",
        '४' => "4",
        '५' => "5",
        '६' => "6",
        '७' => "7",
        '८' => "8",
        '९' => "9",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roman(input: &str) -> String {
        to_output_script(input, "hinglish")
    }

    #[test]
    fn non_roman_modes_return_the_input_unchanged() {
        assert_eq!(to_output_script("कल क्या होगा?", "hindi"), "कल क्या होगा?");
        assert_eq!(
            to_output_script("Please review", "english"),
            "Please review"
        );
    }

    #[test]
    fn basic_words_transliterate_with_final_schwa_deletion() {
        assert_eq!(roman("कल"), "kal");
        assert_eq!(roman("क्या"), "kya");
        assert_eq!(roman("होगा"), "hoga");
        assert_eq!(roman("है"), "hai");
        assert_eq!(roman("नमस्ते"), "namaste");
    }

    #[test]
    fn single_consonant_word_keeps_its_inherent_vowel() {
        assert_eq!(roman("क"), "ka");
    }

    #[test]
    fn anusvara_and_matras_nasalise_and_vowel_correctly() {
        assert_eq!(roman("हिंदी"), "hindi");
        assert_eq!(roman("मैं"), "main");
    }

    #[test]
    fn full_hindi_sentence_reads_in_roman() {
        assert_eq!(roman("कल क्या होगा?"), "kal kya hoga?");
    }

    #[test]
    fn english_and_technical_spans_are_preserved_verbatim() {
        // Latin words, numbers, URLs, emails and code sit in non-Devanagari runs.
        assert_eq!(
            roman("कल Flutter की meeting कब है?"),
            "kal Flutter ki meeting kab hai?"
        );
        assert_eq!(roman("oynix.dev खोलना।"), "oynix.dev kholna");
        assert_eq!(
            roman("getUserById function check करना"),
            "getUserById function check karna"
        );
        assert_eq!(roman("₹10,000 भेजना"), "₹10,000 bhejna");
    }

    #[test]
    fn devanagari_digits_become_ascii() {
        assert_eq!(roman("१२३"), "123");
    }

    #[test]
    fn conjunct_clusters_use_the_virama() {
        assert_eq!(roman("प्रश्न"), "prashn");
        assert_eq!(roman("स्वागत"), "svagat");
    }
}
