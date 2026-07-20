# Offline model manifest

Every downloaded native model is pinned by an exact SHA-256 digest and is
verified before an atomic install. A failed or partial download is never used.

## Primary engines — fast ONNX ASR

Recognition runs on two ONNX engines hosted out of process by
`swar_asr_server` (~20-30x faster than whisper). Each is a multi-file bundle;
every file is pinned by URL, size, and SHA-256 in
`crates/swar_core/src/asr_models.json` (the authoritative digest list) and
verified on download. Pinned to immutable HF revisions.

| Role | Bundle | Files | Size | Install | Revision | License and provenance |
| --- | --- | ---: | ---: | --- | --- | --- |
| English + European ASR (Parakeet) | `models/parakeet-v3/` | 4 | ~670 MB | Default (auto, first launch) | `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8@2bda32ec` | NVIDIA NeMo `parakeet-tdt-0.6b-v3` (base model CC-BY-4.0); sherpa-onnx int8 export. Export repo lists no explicit license tag — verify before redistribution |
| Hindi, Hinglish + 22 Indian languages (IndicConformer) | `models/indic-conformer/` | 17 | ~668 MB | Opt-in (Settings button) | `atharva-again/indic-conformer-600m-quantized@24161a9b` | MIT; int8 ONNX quantization of AI4Bharat `indic-conformer-600m-multilingual` |

Parakeet is the always-on default and downloads once in the background on first
launch (`ensure_parakeet_download`). The Indian-languages pack is **opt-in** — a
user installs it from Settings ("Indian languages" → Download pack,
`install_indic_models`), keeping English-only installs ~668 MB lighter on disk
and ~0.7 GB lighter in RAM. Until it is installed, Hindi/Hinglish/Indian speech
falls back to whisper.

Routing (`swar_asr_server::route`): English → Parakeet; Hindi / Hinglish /
Auto / unset → IndicConformer Hindi head; ta, te, bn, kn, ml, mr, gu, pa, or,
ur → their IndicConformer head. IndicConformer emits native script (Devanagari
for Hindi/Hinglish); the language stage romanises it for the Hinglish and Auto
output modes. Only the 11 routed adapters are downloaded, not all 22. A pack
installed from Settings mid-session is picked up on the next dictation without a
restart (`asr_client` resolves the model dirs per job).

## Fallback engine — whisper.cpp

Whisper decodes only when the fast helper, its models, or a language route is
unavailable, so recognition never breaks. The Apex Hinglish pack was removed:
IndicConformer is now the primary Hinglish engine.

| Role | File | Size | SHA-256 | License and provenance |
| --- | --- | ---: | --- | --- |
| English, Auto, Hinglish fallback | `ggml-small-q5_1.bin` | 190,085,487 bytes | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` | OpenAI Whisper small, MIT, official whisper.cpp q5_1 conversion |
| Hindi fallback | `ggml-hi-small.bin` | 190,085,487 bytes | `6813fed7ffa6c3fa14490c1f1788d2d8b6e3b7badf59a2f75fb4c5c21cf00f3f` | Apache-2.0 Ukta GGML conversion of the IIT Madras `vasista22/whisper-hindi-small` fine-tune; model card identifies Shrutilipi, Vistaar, and FLEURS corpora |
| Voice activity detection | `ggml-silero-v6.2.0.bin` | 885,098 bytes | `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987` | Silero VAD v6.2, MIT, official ggml-org conversion |

On the whisper fallback path the Hindi pack is selected only for explicit Hindi
mode. Auto, English, and Hinglish keep the multilingual model so code-switched
speech is not forced through a monolingual decoder.

## Current local bake-off

The reproducible macOS system-voice suite on 2026-07-19 measured:

| Model and mode | WER | RTF | Decision |
| --- | ---: | ---: | --- |
| Whisper small q5_1, English | 13.2% | 0.08 | Keep as Balanced |
| Whisper small q5_1, Hinglish | 17.4% | 0.31 | Keep as Balanced |
| Whisper small q5_1, Hindi | 57.1% | 0.37 | Reject for explicit Hindi |
| Ukta Hindi small q5_1, Hindi | 42.9% | 0.32 | Better fallback; continue real-speaker evaluation |
| Whisper large-v3-turbo q5_0, Hindi | 50.0% | 1.21 | Reject: slower and less accurate on this gate |

Synthetic speech is a stable regression fixture, not a substitute for diverse
human speakers. No model may be advertised as accurate for Hindi until it also
passes the physical-speaker matrix in `docs/compatibility.md`.
