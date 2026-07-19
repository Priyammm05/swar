use std::f64::consts::PI;

const HALF_TAPS: isize = 16;

/// Band-limited windowed-sinc resampling for the ASR boundary.
///
/// This runs only on a Rust worker after capture. It avoids the high-frequency
/// aliasing of linear interpolation without adding an end-user runtime.
pub(crate) fn to_sample_rate(input: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if input.is_empty() || source_rate == 0 || target_rate == 0 {
        return Vec::new();
    }
    if source_rate == target_rate {
        return input.to_vec();
    }
    let output_len = ((input.len() as u128 * target_rate as u128) / source_rate as u128) as usize;
    let source_per_output = source_rate as f64 / target_rate as f64;
    let cutoff = (target_rate as f64 / source_rate as f64).min(1.0) * 0.94;
    let mut output = Vec::with_capacity(output_len);
    for output_index in 0..output_len {
        let source_position = output_index as f64 * source_per_output;
        let centre = source_position.floor() as isize;
        let mut weighted = 0.0_f64;
        let mut weight_sum = 0.0_f64;
        for tap in -HALF_TAPS..=HALF_TAPS {
            let input_index = centre + tap;
            if !(0..input.len() as isize).contains(&input_index) {
                continue;
            }
            let distance = source_position - input_index as f64;
            let normalized = PI * distance * cutoff;
            let sinc = if normalized.abs() < f64::EPSILON {
                1.0
            } else {
                normalized.sin() / normalized
            };
            let window_position = distance / (HALF_TAPS as f64 + 1.0);
            if window_position.abs() > 1.0 {
                continue;
            }
            let window = 0.5 + 0.5 * (PI * window_position).cos();
            let weight = cutoff * sinc * window;
            weighted += f64::from(input[input_index as usize]) * weight;
            weight_sum += weight;
        }
        output.push(if weight_sum.abs() < f64::EPSILON {
            0.0
        } else {
            (weighted / weight_sum).clamp(-1.0, 1.0) as f32
        });
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_the_common_coreaudio_rate_to_whisper_rate() {
        let output = to_sample_rate(&vec![0.25; 48_000], 48_000, 16_000);
        assert_eq!(output.len(), 16_000);
        assert!(output.iter().all(|sample| (*sample - 0.25).abs() < 0.000_1));
    }

    #[test]
    fn rejects_invalid_boundaries_without_panicking() {
        assert!(to_sample_rate(&[1.0], 0, 16_000).is_empty());
        assert!(to_sample_rate(&[1.0], 16_000, 0).is_empty());
    }
}
