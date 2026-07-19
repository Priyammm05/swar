# Offline model manifest

Every downloaded native model is pinned by an exact SHA-256 digest and is
verified before an atomic install. A failed or partial download is never used.

| Role | File | Size | SHA-256 | License and provenance |
| --- | --- | ---: | --- | --- |
| English, Auto, Hinglish ASR | `ggml-small-q5_1.bin` | 190,085,487 bytes | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` | OpenAI Whisper small, MIT, official whisper.cpp q5_1 conversion |
| Hindi ASR | `ggml-hi-small.bin` | 190,085,487 bytes | `6813fed7ffa6c3fa14490c1f1788d2d8b6e3b7badf59a2f75fb4c5c21cf00f3f` | Apache-2.0 Ukta GGML conversion of the IIT Madras `vasista22/whisper-hindi-small` fine-tune; model card identifies Shrutilipi, Vistaar, and FLEURS corpora |
| Voice activity detection | `ggml-silero-v6.2.0.bin` | 885,098 bytes | `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987` | Silero VAD v6.2, MIT, official ggml-org conversion |

The Hindi pack is selected only for explicit Hindi mode. Auto, English, and
Hinglish keep the multilingual model so code-switched speech is not forced
through a monolingual decoder.

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
