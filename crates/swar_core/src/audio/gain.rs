//! Per-utterance gain normalization for the ASR boundary (swar.md §4).
//!
//! Whisper-family models drop words on very quiet input and garble loud, clipped
//! input. This stage presents the model a consistent level: it measures the
//! utterance, applies a single bounded gain toward an RMS target, and soft-limits
//! any residual peaks. It is a pure transform over the 16 kHz mono buffer — no
//! streaming state, no allocation on the audio callback — and it emits four
//! diagnostic metrics so any "why was this transcript bad" question is answerable
//! from history without ever storing audio.

/// Diagnostic levels for one utterance, measured on the pre-gain signal (except
/// `applied_gain_db`). Stored with the dictation record; never contains audio.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct GainMetrics {
    /// Loudest sample, in dBFS (`-inf` reported as a large negative for silence).
    pub peak_dbfs: f32,
    /// Root-mean-square level, in dBFS.
    pub rms_dbfs: f32,
    /// Percentage of samples at or beyond the clipping rails (|x| >= 0.999).
    pub clipped_pct: f32,
    /// Gain the normalizer actually applied, in dB (0 when it was bypassed).
    pub applied_gain_db: f32,
}

/// Target presentation level (swar.md §4): RMS ~ -20 dBFS, peak ceiling -1 dBFS.
const TARGET_RMS: f32 = 0.1; // 10^(-20/20)
const PEAK_CEILING: f32 = 0.891_25; // 10^(-1/20)
/// Bound the correction so we never amplify a near-silent noise floor into a roar
/// (swar.md §4: max ~±18 dB).
const MAX_GAIN: f32 = 7.943_28; // +18 dB
const MIN_GAIN: f32 = 0.125_89; // -18 dB
/// Below this RMS the buffer is effectively silence; boosting it only amplifies
/// hiss, so the stage bypasses (VAD will drop it anyway).
const SILENCE_RMS: f32 = 0.000_5;

fn to_dbfs(amplitude: f32) -> f32 {
    if amplitude <= 1.0e-9 {
        -120.0
    } else {
        20.0 * amplitude.log10()
    }
}

/// Normalizes one utterance toward the RMS target and soft-limits peaks. Returns
/// the level-adjusted buffer and the metrics measured on the original signal.
pub(crate) fn normalize(input: &[f32]) -> (Vec<f32>, GainMetrics) {
    if input.is_empty() {
        return (
            Vec::new(),
            GainMetrics {
                peak_dbfs: -120.0,
                rms_dbfs: -120.0,
                clipped_pct: 0.0,
                applied_gain_db: 0.0,
            },
        );
    }

    let mut sum_squares = 0.0_f64;
    let mut peak = 0.0_f32;
    let mut clipped = 0_usize;
    for &sample in input {
        let magnitude = sample.abs();
        sum_squares += f64::from(sample) * f64::from(sample);
        if magnitude > peak {
            peak = magnitude;
        }
        if magnitude >= 0.999 {
            clipped += 1;
        }
    }
    let overall_rms = (sum_squares / input.len() as f64).sqrt() as f32;
    // Normalize on the level of the *speech*, not the whole utterance: a
    // pause-heavy dictation has its overall RMS dragged down by the silences,
    // which would over-boost the speech until the limiter clamps it. Measuring
    // over frames above the noise floor keeps the boost honest (plan M1.6).
    let rms = speech_weighted_rms(input, overall_rms);
    let clipped_pct = (clipped as f32 / input.len() as f32) * 100.0;

    // Bypass on silence: nothing worth boosting, and VAD will discard it.
    if rms < SILENCE_RMS {
        return (
            input.to_vec(),
            GainMetrics {
                peak_dbfs: to_dbfs(peak),
                rms_dbfs: to_dbfs(rms),
                clipped_pct,
                applied_gain_db: 0.0,
            },
        );
    }

    let gain = (TARGET_RMS / rms).clamp(MIN_GAIN, MAX_GAIN);
    let output = input
        .iter()
        .map(|&sample| soft_limit(sample * gain))
        .collect::<Vec<f32>>();

    (
        output,
        GainMetrics {
            peak_dbfs: to_dbfs(peak),
            rms_dbfs: to_dbfs(rms),
            clipped_pct,
            applied_gain_db: to_dbfs(gain),
        },
    )
}

/// 20 ms at 16 kHz — the gain stage always runs on the resampled 16 kHz buffer.
const FRAME_SAMPLES: usize = 320;

/// RMS measured over speech frames only (frames whose energy is above the
/// estimated noise floor). Falls back to `overall_rms` when the buffer is too
/// short to frame or too uniform to separate speech from noise, so a clean
/// steady tone still normalizes exactly as before.
fn speech_weighted_rms(input: &[f32], overall_rms: f32) -> f32 {
    if input.len() < FRAME_SAMPLES * 4 {
        return overall_rms;
    }
    let frame_rms: Vec<f32> = input
        .chunks(FRAME_SAMPLES)
        .map(|frame| {
            let sum: f64 = frame.iter().map(|s| f64::from(*s) * f64::from(*s)).sum();
            (sum / frame.len() as f64).sqrt() as f32
        })
        .collect();
    // Noise floor ~ 10th percentile of frame energy; speech is anything clearly
    // above it.
    let mut sorted = frame_rms.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let noise_floor = sorted[sorted.len() / 10];
    let threshold = (noise_floor * 2.0).max(SILENCE_RMS);
    let speech: Vec<f32> = frame_rms.into_iter().filter(|r| *r >= threshold).collect();
    // Need a few real speech frames (~60 ms) to trust the estimate.
    if speech.len() < 3 {
        return overall_rms;
    }
    let sum: f64 = speech.iter().map(|r| f64::from(*r) * f64::from(*r)).sum();
    (sum / speech.len() as f64).sqrt() as f32
}

/// tanh soft knee above the peak ceiling. Leaves the bulk of the signal linear and
/// only rounds off peaks that the gain pushed past -1 dBFS, so louder syllables
/// stay controlled without the hard edges that clipping (and WER) come from.
fn soft_limit(sample: f32) -> f32 {
    let magnitude = sample.abs();
    if magnitude <= PEAK_CEILING {
        return sample;
    }
    let over = (magnitude - PEAK_CEILING) / (1.0 - PEAK_CEILING);
    let limited = PEAK_CEILING + (1.0 - PEAK_CEILING) * over.tanh();
    limited.copysign(sample)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rms_of(samples: &[f32]) -> f32 {
        let sum: f64 = samples.iter().map(|s| f64::from(*s) * f64::from(*s)).sum();
        (sum / samples.len() as f64).sqrt() as f32
    }

    #[test]
    fn quiet_input_is_boosted_toward_the_target() {
        // A -34 dBFS tone (~0.02 RMS) is exactly the "words get dropped" case.
        let quiet = vec![0.02_f32; 16_000];
        let (out, metrics) = normalize(&quiet);
        assert!(metrics.applied_gain_db > 6.0, "expected real boost");
        // Brought close to the -20 dBFS (0.1) RMS target.
        assert!((rms_of(&out) - TARGET_RMS).abs() < 0.02);
    }

    #[test]
    fn boost_is_capped_so_silence_hiss_is_not_amplified_to_a_roar() {
        let faint = vec![0.002_f32; 16_000]; // above the silence floor, very quiet
        let (_out, metrics) = normalize(&faint);
        assert!(metrics.applied_gain_db <= 18.0 + 0.01);
    }

    #[test]
    fn pure_silence_is_bypassed_not_amplified() {
        let silence = vec![0.0_f32; 1_000];
        let (out, metrics) = normalize(&silence);
        assert_eq!(metrics.applied_gain_db, 0.0);
        assert_eq!(out, silence);
    }

    #[test]
    fn peaks_stay_within_the_rails_after_gain() {
        // Loud, spiky input that a naive gain would push past 1.0.
        let mut loud = vec![0.3_f32; 16_000];
        loud[0] = 0.95;
        loud[1] = -0.95;
        let (out, _metrics) = normalize(&loud);
        assert!(out.iter().all(|s| s.abs() <= 1.0));
    }

    #[test]
    fn metrics_report_clipping() {
        let mut clipped = vec![0.5_f32; 1_000];
        for sample in clipped.iter_mut().take(100) {
            *sample = 1.0;
        }
        let (_out, metrics) = normalize(&clipped);
        assert!((metrics.clipped_pct - 10.0).abs() < 0.01);
    }

    #[test]
    fn empty_input_is_safe() {
        let (out, metrics) = normalize(&[]);
        assert!(out.is_empty());
        assert_eq!(metrics.applied_gain_db, 0.0);
    }

    #[test]
    fn pause_heavy_audio_is_not_over_boosted() {
        // A short burst of on-target speech (0.1 RMS) inside mostly-silent
        // audio. The overall RMS is dragged far below target by the pauses; a
        // naive normalizer would boost the whole thing several dB. Speech-
        // weighted RMS sees the speech is already at target and barely moves it.
        let mut samples = vec![0.005_f32; 16_000];
        for sample in samples.iter_mut().skip(7_000).take(2_000) {
            *sample = 0.1;
        }
        let (_out, metrics) = normalize(&samples);
        assert!(
            metrics.applied_gain_db.abs() < 3.0,
            "speech already at target should barely move; got {} dB",
            metrics.applied_gain_db
        );
    }

    #[test]
    fn steady_quiet_tone_still_normalizes_to_target() {
        // A uniform quiet tone has no pauses to exclude, so speech-weighting must
        // not change the existing behaviour: it is still boosted to the target.
        let quiet = vec![0.02_f32; 16_000];
        let (out, metrics) = normalize(&quiet);
        assert!(metrics.applied_gain_db > 6.0);
        assert!((rms_of(&out) - TARGET_RMS).abs() < 0.02);
    }
}
