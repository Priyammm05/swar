const FRAME_MILLISECONDS: usize = 20;
const PRE_PAD_MILLISECONDS: usize = 350;
const POST_PAD_MILLISECONDS: usize = 350;
const MINIMUM_SPEECH_MILLISECONDS: usize = 120;
const ABSOLUTE_RMS_FLOOR: f64 = 0.0025;

pub(crate) struct SpeechAnalysis {
    pub samples: Vec<f32>,
    pub speech_duration_ms: u64,
}

/// Conservative energy gate before Silero. Silero remains the authoritative
/// segmenter inside whisper.cpp; this gate only prevents obvious silence from
/// reaching a generative decoder and producing hallucinated text.
pub(crate) fn retain_probable_speech(samples: &[f32], sample_rate: u32) -> SpeechAnalysis {
    if samples.is_empty() || sample_rate == 0 {
        return SpeechAnalysis {
            samples: Vec::new(),
            speech_duration_ms: 0,
        };
    }
    let frame_samples = (sample_rate as usize * FRAME_MILLISECONDS / 1_000).max(1);
    let mut levels = samples
        .chunks(frame_samples)
        .map(|frame| {
            (frame
                .iter()
                .map(|sample| f64::from(*sample) * f64::from(*sample))
                .sum::<f64>()
                / frame.len() as f64)
                .sqrt()
        })
        .collect::<Vec<_>>();
    let mut sorted = levels.clone();
    sorted.sort_by(f64::total_cmp);
    let noise_floor = sorted[sorted.len() / 5];
    let threshold = ABSOLUTE_RMS_FLOOR.max(noise_floor * 3.0);
    let active = levels
        .iter_mut()
        .enumerate()
        .filter_map(|(index, level)| (*level >= threshold).then_some(index))
        .collect::<Vec<_>>();
    let speech_duration_ms = active.len() * FRAME_MILLISECONDS;
    if speech_duration_ms < MINIMUM_SPEECH_MILLISECONDS {
        return SpeechAnalysis {
            samples: Vec::new(),
            speech_duration_ms: 0,
        };
    }
    let pre_frames = PRE_PAD_MILLISECONDS / FRAME_MILLISECONDS;
    let post_frames = POST_PAD_MILLISECONDS / FRAME_MILLISECONDS;
    let start_frame = active[0].saturating_sub(pre_frames);
    let end_frame = (active[active.len() - 1] + post_frames + 1).min(levels.len());
    let start = start_frame * frame_samples;
    let end = (end_frame * frame_samples).min(samples.len());
    SpeechAnalysis {
        samples: samples[start..end].to_vec(),
        speech_duration_ms: speech_duration_ms as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_silence_before_it_can_hallucinate() {
        let analysis = retain_probable_speech(&vec![0.0; 16_000], 16_000);
        assert!(analysis.samples.is_empty());
        assert_eq!(analysis.speech_duration_ms, 0);
    }

    #[test]
    fn retains_speech_with_edge_padding() {
        let mut samples = vec![0.0; 16_000];
        samples[6_400..9_600].fill(0.1);
        let analysis = retain_probable_speech(&samples, 16_000);
        assert!(!analysis.samples.is_empty());
        assert!(analysis.samples.len() > 3_200);
        assert_eq!(analysis.speech_duration_ms, 200);
    }
}
