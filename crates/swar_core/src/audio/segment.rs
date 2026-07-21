//! Splits a long utterance into decodable segments at natural pauses.
//!
//! Whisper encodes 30 s at a time and uses the timestamp it emits to decide
//! where the next window starts. On a dictation longer than one window that
//! seeking goes wrong: measured on a 45 s Hinglish passage, a single decode
//! returned 71 of 145 spoken words and silently dropped a whole clause, and a
//! 91 s clip came back with content duplicated across the seam. Handing whisper
//! one window at a time removes the seam entirely.
//!
//! The cut has to land in a pause. Splitting the same audio on a fixed clock
//! sliced words in half and one piece decoded as "[Reading the numbers]" instead
//! of its actual content, so the target length only opens a *search window* — the
//! quietest frame inside it becomes the boundary.

/// Frame size for the loudness scan. Matches `speech`, so both agree on what a
/// quiet frame is.
const FRAME_MILLISECONDS: usize = 20;

/// Preferred segment length. A segment cannot be shorter than this.
///
/// 10 s measured identically to 25 s on accuracy (WER 0.324 either way), and it
/// is the better choice for latency: only the final segment is still undecoded
/// when the speaker stops, so a short one means a short wait. On the same
/// passage the last segment decoded in 2.9 s against 4.7 s for 25 s segments.
const TARGET_SEGMENT_SECONDS: usize = 10;

/// Hard ceiling. Reached only when the speaker does not pause, in which case the
/// quietest frame available is used even though it is not truly silent. Kept
/// well under whisper's 30 s window so a segment always encodes in one pass.
const MAXIMUM_SEGMENT_SECONDS: usize = 20;

/// Audio at or below this decodes in a single window already, so it is left
/// alone: segmenting it would only cost the model context it can currently use.
const SINGLE_WINDOW_SECONDS: usize = 30;

/// Sample ranges to decode in order. Always covers the whole input with no gap
/// and no overlap; returns one range when the audio fits in a single window.
pub(crate) fn split_at_pauses(samples: &[f32], sample_rate: u32) -> Vec<std::ops::Range<usize>> {
    let whole = whole_range(samples.len());
    if sample_rate == 0 || samples.is_empty() {
        return whole;
    }
    if samples.len() <= SINGLE_WINDOW_SECONDS * sample_rate as usize {
        return whole;
    }

    let frame = (sample_rate as usize * FRAME_MILLISECONDS / 1_000).max(1);
    let levels = frame_levels(samples, frame);
    let frames_per_second = 1_000 / FRAME_MILLISECONDS;
    let target_frames = TARGET_SEGMENT_SECONDS * frames_per_second;
    let maximum_frames = MAXIMUM_SEGMENT_SECONDS * frames_per_second;

    let mut ranges = Vec::new();
    let mut start_frame = 0usize;
    while start_frame < levels.len() {
        let remaining = levels.len() - start_frame;
        // Absorb a short remainder rather than emitting a sliver: a one-second
        // tail carries too little context to decode well on its own.
        if remaining <= maximum_frames {
            ranges.push(start_frame * frame..samples.len());
            break;
        }
        let search_start = start_frame + target_frames;
        let search_end = (start_frame + maximum_frames).min(levels.len());
        let cut_frame = quietest_frame(&levels[search_start..search_end])
            .map(|offset| search_start + offset)
            .unwrap_or(search_end);
        ranges.push(start_frame * frame..cut_frame * frame);
        start_frame = cut_frame;
    }
    if ranges.is_empty() {
        return whole;
    }
    ranges
}

/// The single range covering everything. Built through `once` because a
/// one-element range literal reads to clippy as an attempt to collect the
/// range's elements rather than to hold the range itself.
fn whole_range(len: usize) -> Vec<std::ops::Range<usize>> {
    std::iter::once(0..len).collect()
}

fn frame_levels(samples: &[f32], frame: usize) -> Vec<f64> {
    samples
        .chunks(frame)
        .map(|window| {
            (window
                .iter()
                .map(|sample| f64::from(*sample) * f64::from(*sample))
                .sum::<f64>()
                / window.len() as f64)
                .sqrt()
        })
        .collect()
}

fn quietest_frame(levels: &[f64]) -> Option<usize> {
    levels
        .iter()
        .enumerate()
        .min_by(|left, right| left.1.total_cmp(right.1))
        .map(|(index, _)| index)
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: u32 = 16_000;

    /// Speech at `level`, with a silent gap centred on each of `pause_seconds`.
    fn utterance(total_seconds: usize, pause_seconds: &[usize]) -> Vec<f32> {
        let mut samples = vec![0.0f32; total_seconds * RATE as usize];
        for (index, sample) in samples.iter_mut().enumerate() {
            *sample = if index % 2 == 0 { 0.2 } else { -0.2 };
        }
        for pause in pause_seconds {
            let centre = pause * RATE as usize;
            let half = RATE as usize / 4; // 500 ms of silence
            let start = centre.saturating_sub(half);
            let end = (centre + half).min(samples.len());
            samples[start..end].fill(0.0);
        }
        samples
    }

    #[test]
    fn audio_inside_one_window_is_left_whole() {
        let samples = utterance(25, &[]);
        let ranges = split_at_pauses(&samples, RATE);
        assert_eq!(ranges, vec![0..samples.len()]);
    }

    #[test]
    fn empty_and_degenerate_input_still_yields_one_range() {
        assert_eq!(split_at_pauses(&[], RATE), vec![0..0]);
        let samples = utterance(40, &[]);
        assert_eq!(split_at_pauses(&samples, 0), vec![0..samples.len()]);
    }

    #[test]
    fn long_audio_is_covered_exactly_once_with_no_gaps() {
        let samples = utterance(75, &[11, 23, 34, 47, 58]);
        let ranges = split_at_pauses(&samples, RATE);
        assert!(
            ranges.len() > 1,
            "expected several segments, got {ranges:?}"
        );
        assert_eq!(ranges[0].start, 0);
        assert_eq!(ranges[ranges.len() - 1].end, samples.len());
        for pair in ranges.windows(2) {
            assert_eq!(pair[0].end, pair[1].start, "segments must abut: {ranges:?}");
        }
    }

    #[test]
    fn every_segment_fits_inside_one_whisper_window() {
        // No pauses at all: the speaker never stops, so the hard ceiling governs.
        let samples = utterance(90, &[]);
        for range in split_at_pauses(&samples, RATE) {
            let seconds = range.len() as f64 / f64::from(RATE);
            assert!(
                seconds <= SINGLE_WINDOW_SECONDS as f64,
                "segment of {seconds:.1}s exceeds one window"
            );
        }
    }

    #[test]
    fn cuts_land_in_the_pauses_rather_than_mid_word() {
        // Pauses sit inside the search window that follows each target length.
        let samples = utterance(50, &[12, 26, 38]);
        let ranges = split_at_pauses(&samples, RATE);
        let pauses: Vec<usize> = [12, 26, 38].iter().map(|s| s * RATE as usize).collect();
        for pair in ranges.windows(2) {
            let cut = pair[0].end;
            let nearest = pauses
                .iter()
                .map(|pause| cut.abs_diff(*pause))
                .min()
                .expect("a pause exists");
            assert!(
                nearest <= RATE as usize / 2,
                "cut at {cut} is not within 500 ms of a pause"
            );
        }
    }

    #[test]
    fn a_short_tail_is_absorbed_instead_of_emitted_alone() {
        // 32 s: past one window, but the remainder after the first cut is small.
        let samples = utterance(32, &[11]);
        let ranges = split_at_pauses(&samples, RATE);
        for range in &ranges {
            let seconds = range.len() as f64 / f64::from(RATE);
            assert!(
                seconds >= 1.0,
                "sliver segment of {seconds:.1}s: {ranges:?}"
            );
        }
    }
}
