// torchaudio.MelSpectrogram(sr=16000,n_fft=512,win=400,hop=160,f_min=0,f_max=8000,
// n_mels=80,power=2,center=True,pad=reflect,mel_scale=htk,norm=None) + log + per-mel znorm.
//
// This is a direct numeric port validated against the torchaudio reference
// (maxdiff 0.0036). The index-based loops deliberately mirror the reference across
// several parallel arrays (filterbank x power, bin_hz x filter), so the readability
// lint that prefers iterators does not apply.
#![allow(clippy::needless_range_loop)]

use rustfft::{num_complex::Complex, FftPlanner};

const NFFT: usize = 512;
const WIN: usize = 400;
const HOP: usize = 160;
const NMEL: usize = 80;
const SR: f32 = 16000.0;
const NFREQ: usize = NFFT / 2 + 1; // 257

fn hz_to_mel_htk(f: f32) -> f32 {
    2595.0 * (1.0 + f / 700.0).log10()
}
fn mel_to_hz_htk(m: f32) -> f32 {
    700.0 * (10f32.powf(m / 2595.0) - 1.0)
}

fn mel_filterbank() -> Vec<[f32; NFREQ]> {
    // triangular htk filters, norm=None
    let m_min = hz_to_mel_htk(0.0);
    let m_max = hz_to_mel_htk(8000.0);
    let mut mpts = [0f32; NMEL + 2];
    for i in 0..NMEL + 2 {
        mpts[i] = mel_to_hz_htk(m_min + (m_max - m_min) * i as f32 / (NMEL + 1) as f32);
    }
    let bin_hz: Vec<f32> = (0..NFREQ).map(|k| k as f32 * SR / NFFT as f32).collect();
    let mut fb = vec![[0f32; NFREQ]; NMEL];
    for m in 0..NMEL {
        let (l, c, r) = (mpts[m], mpts[m + 1], mpts[m + 2]);
        for k in 0..NFREQ {
            let f = bin_hz[k];
            let up = (f - l) / (c - l);
            let dn = (r - f) / (r - c);
            let v = up.min(dn).max(0.0);
            fb[m][k] = v;
        }
    }
    fb
}

fn reflect_pad(x: &[f32], p: usize) -> Vec<f32> {
    let n = x.len();
    let mut out = Vec::with_capacity(n + 2 * p);
    for j in 0..p {
        out.push(x[p - j]);
    } // x[p],x[p-1],...,x[1]
    out.extend_from_slice(x);
    for j in 0..p {
        out.push(x[n - 2 - j]);
    } // x[n-2],...,x[n-1-p]
    out
}

pub fn log_mel(samples: &[f32]) -> Vec<[f32; NMEL]> {
    // hann periodic window of length WIN, placed centered in a NFFT frame
    let mut win = [0f32; NFFT];
    let off = (NFFT - WIN) / 2; // 56
    for n in 0..WIN {
        win[off + n] = 0.5 - 0.5 * (2.0 * std::f32::consts::PI * n as f32 / WIN as f32).cos();
    }
    let padded = reflect_pad(samples, NFFT / 2);
    let nframes = 1 + (padded.len() - NFFT) / HOP;
    let fb = mel_filterbank();
    let mut planner = FftPlanner::<f32>::new();
    let fft = planner.plan_fft_forward(NFFT);
    let mut frames: Vec<[f32; NMEL]> = Vec::with_capacity(nframes);
    for t in 0..nframes {
        let start = t * HOP;
        let mut buf: Vec<Complex<f32>> = (0..NFFT)
            .map(|i| Complex {
                re: padded[start + i] * win[i],
                im: 0.0,
            })
            .collect();
        fft.process(&mut buf);
        let mut power = [0f32; NFREQ];
        for k in 0..NFREQ {
            power[k] = buf[k].re * buf[k].re + buf[k].im * buf[k].im;
        }
        let mut mel = [0f32; NMEL];
        for m in 0..NMEL {
            let mut s = 0f32;
            for k in 0..NFREQ {
                s += fb[m][k] * power[k];
            }
            mel[m] = (s + 1e-9).ln();
        }
        frames.push(mel);
    }
    // per-mel-channel z-norm over time
    for m in 0..NMEL {
        let mean: f32 = frames.iter().map(|f| f[m]).sum::<f32>() / nframes as f32;
        let var: f32 = frames.iter().map(|f| (f[m] - mean).powi(2)).sum::<f32>() / nframes as f32;
        let sd = var.sqrt() + 1e-5;
        for f in frames.iter_mut() {
            f[m] = (f[m] - mean) / sd;
        }
    }
    frames
}
