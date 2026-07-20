//! IndicConformer (AI4Bharat) RNNT decoding in pure Rust via onnxruntime (`ort`).
//!
//! This is a faithful port of the reference Python decoder: a shared encoder, a
//! split joint network, an RNNT prediction network, and a per-language adapter
//! head, driven by a greedy transducer loop. It was validated to reproduce the
//! reference transcript exactly on clean Hindi and to transcribe real Hinglish
//! correctly. Audio features come from `mel` (matched to torchaudio numerically).

use std::{collections::HashMap, path::PathBuf};

use ort::{session::Session, value::Tensor};

use crate::mel;

const BLANK_ID: i32 = 256;
const ENC_DIM: usize = 1024;
const JOINT_DIM: usize = 640;
const MAX_SYMBOLS: usize = 400;

/// Owns the shared IndicConformer graphs plus lazily-loaded per-language adapters
/// and vocabularies. One instance serves every Indian language.
pub struct IndicConformer {
    model_dir: PathBuf,
    encoder: Session,
    joint_enc: Session,
    joint_pred: Session,
    joint_pre_net: Session,
    rnnt_decoder: Session,
    // Per-language: the adapter head session and the token vocabulary.
    adapters: HashMap<String, Session>,
    vocabs: HashMap<String, Vec<String>>,
}

impl IndicConformer {
    /// Loads the shared graphs. `model_dir` is the IndicConformer folder holding
    /// `onnx/` and `config/`.
    pub fn new(model_dir: PathBuf) -> Result<Self, String> {
        let onnx = model_dir.join("onnx");
        let load = |name: &str| -> Result<Session, String> {
            Session::builder()
                .and_then(|b| b.commit_from_file(onnx.join(name)))
                .map_err(|e| format!("load {name}: {e}"))
        };
        Ok(Self {
            encoder: load("encoder_quantized_int8.onnx")?,
            joint_enc: load("joint_enc_quantized_int8.onnx")?,
            joint_pred: load("joint_pred_quantized_int8.onnx")?,
            joint_pre_net: load("joint_pre_net_quantized_int8.onnx")?,
            rnnt_decoder: load("rnnt_decoder_quantized_int8.onnx")?,
            adapters: HashMap::new(),
            vocabs: HashMap::new(),
            model_dir,
        })
    }

    fn ensure_lang(&mut self, lang: &str) -> Result<(), String> {
        if !self.adapters.contains_key(lang) {
            let path = self
                .model_dir
                .join("onnx/adapters")
                .join(format!("joint_post_net_{lang}_quantized_int8.onnx"));
            let sess = Session::builder()
                .and_then(|b| b.commit_from_file(&path))
                .map_err(|e| format!("load adapter {lang}: {e}"))?;
            self.adapters.insert(lang.to_owned(), sess);
        }
        if !self.vocabs.contains_key(lang) {
            let text = std::fs::read_to_string(self.model_dir.join("config/vocab.json"))
                .map_err(|e| e.to_string())?;
            let value: serde_json::Value =
                serde_json::from_str(&text).map_err(|e| e.to_string())?;
            let vocab: Vec<String> = serde_json::from_value(value[lang].clone())
                .map_err(|_| format!("vocab for {lang} missing"))?;
            self.vocabs.insert(lang.to_owned(), vocab);
        }
        Ok(())
    }

    /// Transcribes 16 kHz mono `samples` in `lang` (e.g. "hi", "ta"), returning
    /// text in the language's native script.
    pub fn transcribe(&mut self, samples: &[f32], lang: &str) -> Result<String, String> {
        self.ensure_lang(lang)?;

        // Features: [80, T] row-major.
        let frames = mel::log_mel(samples);
        let tt = frames.len();
        if tt == 0 {
            return Ok(String::new());
        }
        let mut feat = vec![0f32; 80 * tt];
        for (ti, frame) in frames.iter().enumerate() {
            for m in 0..80 {
                feat[m * tt + ti] = frame[m];
            }
        }

        // Encoder -> [1, 1024, Tp]; transpose to [1, Tp, 1024]; joint_enc -> [1, Tp, 640].
        // Scope the encoder/joint_enc outputs so their borrow of `self` ends
        // before the RNNT loop calls `self.decode_pred` (SessionOutputs hold their
        // session borrow until dropped).
        let (tp, enc_output) = {
            let ft =
                Tensor::from_array(([1i64, 80, tt as i64], feat)).map_err(|e| e.to_string())?;
            let ln = Tensor::from_array(([1i64], vec![tt as i64])).map_err(|e| e.to_string())?;
            let eo = self
                .encoder
                .run(ort::inputs! {"audio_signal"=>ft, "length"=>ln})
                .map_err(|e| e.to_string())?;
            let (es, ed) = extract(&eo, "outputs")?;
            let tp = es[2] as usize;
            let mut enct = vec![0f32; tp * ENC_DIM];
            for ch in 0..ENC_DIM {
                for ti in 0..tp {
                    enct[ti * ENC_DIM + ch] = ed[ch * tp + ti];
                }
            }
            let jt = Tensor::from_array(([1i64, tp as i64, ENC_DIM as i64], enct))
                .map_err(|e| e.to_string())?;
            let jo = self
                .joint_enc
                .run(ort::inputs! {"input"=>jt})
                .map_err(|e| e.to_string())?;
            let (_, enc_output) = extract(&jo, "output")?;
            (tp, enc_output)
        };

        // Greedy RNNT.
        let mut pred = vec![BLANK_ID];
        let mut pred_cur = self.decode_pred(&pred)?;
        let mut t = 0usize;
        while t < tp && pred.len() < MAX_SYMBOLS {
            let base = t * JOINT_DIM;
            let joint_in: Vec<f32> = (0..JOINT_DIM)
                .map(|i| enc_output[base + i] + pred_cur[i])
                .collect();
            // Scope these outputs too, so their `self` borrows end before the
            // `self.decode_pred` call below.
            let k = {
                let pt = Tensor::from_array(([1i64, 1, JOINT_DIM as i64], joint_in))
                    .map_err(|e| e.to_string())?;
                let po = self
                    .joint_pre_net
                    .run(ort::inputs! {"input"=>pt})
                    .map_err(|e| e.to_string())?;
                let (_, pre) = extract(&po, "output")?;
                let pt2 = Tensor::from_array(([1i64, 1, JOINT_DIM as i64], pre))
                    .map_err(|e| e.to_string())?;
                let adapter = self.adapters.get_mut(lang).expect("adapter ensured");
                let lo = adapter
                    .run(ort::inputs! {"input"=>pt2})
                    .map_err(|e| e.to_string())?;
                let (_, logits) = extract(&lo, "output")?;
                argmax(&logits) as i32
            };
            if k == BLANK_ID {
                t += 1;
            } else {
                pred.push(k);
                pred_cur = self.decode_pred(&pred)?;
            }
        }

        let vocab = &self.vocabs[lang];
        let mut out = String::new();
        let mut prev = -1i32;
        for &idx in &pred[1..] {
            if idx != prev && idx != BLANK_ID && (idx as usize) < vocab.len() {
                out.push_str(&vocab[idx as usize]);
            }
            prev = idx;
        }
        Ok(out.replace('\u{2581}', " ").trim().to_owned())
    }

    /// Runs the prediction network over the current token sequence and returns the
    /// projected last embedding (`joint_pred` output) used as `pred_current`.
    fn decode_pred(&mut self, pred: &[i32]) -> Result<Vec<f32>, String> {
        let u = pred.len();
        let tg =
            Tensor::from_array(([1i64, u as i64], pred.to_vec())).map_err(|e| e.to_string())?;
        let tl = Tensor::from_array(([1i64], vec![u as i32])).map_err(|e| e.to_string())?;
        let z1 = Tensor::from_array(([2i64, 1, JOINT_DIM as i64], vec![0f32; 2 * JOINT_DIM]))
            .map_err(|e| e.to_string())?;
        let z2 = Tensor::from_array(([2i64, 1, JOINT_DIM as i64], vec![0f32; 2 * JOINT_DIM]))
            .map_err(|e| e.to_string())?;
        let ro = self
            .rnnt_decoder
            .run(
                ort::inputs! {"targets"=>tg,"target_length"=>tl,"states.1"=>z1,"onnx::Slice_3"=>z2},
            )
            .map_err(|e| e.to_string())?;
        let (s, dd) = extract(&ro, "outputs")?; // [1, 640, U]
        let uu = s[2] as usize;
        let last: Vec<f32> = (0..JOINT_DIM).map(|i| dd[i * uu + (uu - 1)]).collect();
        let lt =
            Tensor::from_array(([1i64, 1, JOINT_DIM as i64], last)).map_err(|e| e.to_string())?;
        let po = self
            .joint_pred
            .run(ort::inputs! {"input"=>lt})
            .map_err(|e| e.to_string())?;
        let (_, pc) = extract(&po, "output")?;
        Ok(pc)
    }
}

fn extract(
    outputs: &ort::session::SessionOutputs,
    name: &str,
) -> Result<(Vec<i64>, Vec<f32>), String> {
    let (shape, data) = outputs[name]
        .try_extract_tensor::<f32>()
        .map_err(|e| e.to_string())?;
    Ok((shape.iter().copied().collect(), data.to_vec()))
}

fn argmax(v: &[f32]) -> usize {
    let mut best = 0;
    let mut best_v = f32::NEG_INFINITY;
    for (i, &x) in v.iter().enumerate() {
        if x > best_v {
            best_v = x;
            best = i;
        }
    }
    best
}
