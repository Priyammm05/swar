# swar — Master Spec (V1, Reconciled)

**Product:** swar (स्वर) — an offline, India-first voice keyboard for macOS and Windows.
**Status:** This document supersedes both the Build Plan and the Engine & Architecture Spec wherever they conflict. Everything not contradicted here (repo structure, UI spec, data model, phase details) remains as written in the Build Plan.
**Promise:** Speak anywhere. Your voice and text never leave your computer.

---

# Part I — Locked decisions

These were the four open conflicts between the two source documents. They are now resolved. Do not reopen them without a benchmark result or a product review.

## D1. Language scope: English + Hindi + Hinglish

- V1 ships **English**, **Hindi in Devanagari**, and **Hinglish** (Latin-script Hindi mixed with English). This is the approved product scope as of 2026-07-19.
- Hindi has its own model route, golden benchmark, and Unicode insertion coverage. It is not silently mapped to English or Hinglish.
- The moat is Hinglish-in-Roman. Mixed-language speech is **never translated** and never force-normalized into either pure English or pure Hindi.
- Language modes in Settings for V1: `Auto`, `English`, `Hindi`, `Hinglish`.

Canonical behavior example:

> **Spoken:** "Kal Niyo ke Kafka consumer wale PR ko review karna, and check if deployment ready hai."
> **Output:** "Kal Niyo ke Kafka consumer wale PR ko review karna, and check if deployment ready hai."

Structure may improve. Language mixture may not change.

## D2. ASR default: language-routed Whisper *small* q5, always warm

- **Default (swar Balanced):** official multilingual Whisper **small** q5_1 for Auto, English, and Hinglish, plus a pinned Hindi-fine-tuned **small** q5_1 pack for explicit Hindi. Each is about 190 MB and runs through whisper.cpp.
- **Opt-in (swar Accurate):** Hindi-tuned **large-v3-turbo**, quantized, ~500 MB. Available as a download; becomes default *only* if it passes the Phase 11 bake-off latency gates on the full hardware matrix.
- **Fallback (swar Lite):** Whisper base multilingual, quantized, for old hardware.
- Rationale: the product promise is *final text under 1 second after shortcut release*. With streaming partials from a warm small model, only the audio tail needs decoding at release. Turbo cannot reliably hit that on an 8 GB M1 or an AVX-less Windows box. Accuracy-first defaults break the "feels like a system feature" experience; accuracy is an upgrade, not the baseline.
- Never ship English-only `.en` checkpoints.
- **License gate:** the fine-tuned checkpoint's license and *training-data provenance* must pass review **before** it enters the bake-off. Community Hugging Face fine-tunes often inherit unclear dataset licensing. No benchmarking of unshippable models.

## D3. Cleanup: deterministic always, LLM by routing — with a hard validator

Both source docs were half right. The Engine Spec is right that **self-correction resolution is the product** ("meet on tuesday scratch that wednesday" → "meet on Wednesday"). The Build Plan is right that running an LLM on every utterance is wasted latency. The resolution:

```text
Raw ASR
    ↓
Deterministic normalisation          (always runs, <10 ms)
    ↓
Fast-path classifier                 (route)
    ├── simple utterance ──────────→ insert
    └── complex utterance
            ↓
        Local LLM cleanup            (embedded llama.cpp)
            ↓
        Protected-token validator    (hard gate)
            ├── pass → insert LLM output
            └── fail → insert deterministic output
```

**Routing rules — the LLM runs only when one or more is true:**
- Writing mode is Intent
- Utterance has multiple clauses / sentences
- A self-correction cue is detected ("sorry", "scratch that", "no wait", "matlab", "nahi nahi", "I mean")
- Spoken list markers are present
- The user issues an explicit formatting request ("make this an email")

Short simple dictations ("haan theek hai, kal milte hain") go straight through deterministic cleanup. Most dictations should never touch the LLM.

**The validator is non-negotiable.** A prompt instruction ("never change numbers") is a hope; the validator is an enforcement mechanism. Before accepting any LLM rewrite, diff against the deterministic output for: numbers, currency amounts, dates, times, names/entities, URLs, emails, file paths, code identifiers, negation, and language mixture. Any unexplained change → discard the rewrite, use the deterministic output, log error code `swar-INTENT-004`. One silently corrupted UPI amount ends user trust permanently.

**Restraint rule:** only *clear* self-corrections are resolved. "I actually enjoyed the movie" is not a correction and must survive untouched. When confidence is low, do nothing.

## D4. Model choice for cleanup: benchmark 1.7B vs 3B before locking; plan the LoRA

- Candidates: **Qwen3-1.7B** (Q4/Q5 GGUF) vs a **3B-class instruct** model (Q4 GGUF).
- "3B is the floor" is an assertion, not a measurement. Constrained editing with a strict few-shot prompt is far easier than open generation; a 1.7B may clear the bar at half the download (~1 GB vs ~2 GB) and half the RAM.
- Decision is made by the Hinglish cleanup golden-test suite (Part IV), scored on: correction accuracy, meaning preservation, protected-token preservation, language-mixture preservation, and latency on the low-end hardware tier.
- **Named workstream, not a footnote:** a **LoRA fine-tune of the smaller model** on a few-thousand-pair Hinglish cleanup dataset. A tuned 1.7B very likely beats a prompted 3B. This is the compounding moat (see the flywheel, D7).

## D5. Memory strategy: keep-warm by hardware tier — never load-after-release

The Engine Spec's load→transcribe→unload→load-LLM→clean→unload swap dance adds seconds per dictation and kills the instant feel. Replace with tiers:

| Tier | ASR model | Cleanup LLM |
|---|---|---|
| 16 GB+ RAM, plugged in | Always warm | Warm with idle timeout (default 10 min) |
| 8 GB RAM | Always warm (small model, ~500 MB resident) | Load on demand; the fast-path classifier means most dictations never trigger it |
| Battery saver | Unload after idle period | Never resident; on-demand only |

Hard rule (unchanged from the Build Plan): **model load must never happen between shortcut release and insertion** if it can possibly be avoided. Use mmap for all model files. Never hold ASR + LLM decoding concurrently on the 8 GB tier — finish ASR, then run cleanup.

## D6. Runtime: embedded only — no Ollama, no Python, no faster-whisper

- **ASR:** whisper.cpp, vendored at a pinned revision, statically linked via `crates/swar_whisper`.
- **Cleanup:** llama.cpp, vendored at a pinned revision, statically linked via `crates/swar_llama`.
- **VAD:** **Silero VAD** via whisper.cpp's native ggml Silero support. One integration, ~2 MB, no ONNX runtime. This closes the Build Plan's vague "whisper.cpp-supported VAD or a small local VAD."
- **Banned in the shipped app:** Ollama (external user-installed dependency), faster-whisper (Python), ctranslate2 (packaging risk on the Catalina / no-AVX compatibility matrix), any user-facing Python runtime.
- Ollama and Python remain fine for *development*: prompt prototyping, model conversion, benchmarking, LoRA training.

## D7. The self-improvement flywheel (new — in neither source doc)

The history table already stores `raw_text`, `final_text`, and `was_user_edited`. When a user edits an LLM-cleaned dictation, that edit is a **labeled training example** for exactly the failure the prompt missed.

- Add a local, **opt-in** export: `(raw_text, model_output, user_corrected_text)` triples, exportable as JSONL from Settings → Storage.
- These triples feed the LoRA workstream (D4).
- Fully local, fully opt-in, off by default. No telemetry pipeline — the user exports the file themselves if they choose to contribute or self-tune.
- This is the moat that compounds: nobody can copy the Hinglish cleanup quality without the correction data, and the correction data comes from real usage.

---

# Part II — The pipeline (authoritative)

```text
1. Capture      hotkey down → mic → Rust lock-free ring buffer      (cpal: CoreAudio / WASAPI)
2. VAD          Silero via whisper.cpp; 200–400 ms pre-roll,
                200–500 ms post-roll; never clip syllables
3. ASR          warm Whisper small int8 (Hindi-tuned), streaming
                partials while speaking; only the tail decodes
                after key-up
4. Cleanup      deterministic pass → fast-path classifier →
                optional llama.cpp LLM → protected-token validator
5. Context      foreground app *name* passed to the cleanup prompt
                (Slack → casual, Mail → structured); never persisted,
                honors the excluded-apps privacy list
6. Insert       Tier 1 AX / UIA direct insertion →
                Tier 2 clipboard paste with save/restore →
                Tier 3 copy-only fallback
7. Record       history row + daily metrics, transactional;
                audio buffer zeroed and released; no audio saved
```

All heavy work in Rust / C++ threads. Flutter receives only small events (`PartialTranscriptChanged`, `AudioLevelChanged` throttled to ≤30 Hz, state transitions). Raw PCM never crosses into Dart. The Rust dictation state machine is the single source of truth.

**State machine amendment (fixes a gap in the Build Plan):** a new recording session **may begin** while the previous session is in `Cleaning`, `IntentProcessing`, or `Inserting`. Sessions pipeline; only *recording* is exclusive. Fast talkers must never feel blocked. Insertions execute in completion order per target field.

---

# Part III — The cleanup system prompt (the missing artifact)

This prompt is a **versioned, tested artifact** at `models/prompts/cleanup-v1.txt` with its own golden tests. Changing it requires the golden suite to pass. The worked examples are the single biggest quality lever — small models obey examples, not adjectives.

```text
You are swar's local dictation editor. Convert spoken text into the text
the speaker intended to write.

Rules:
1. Add punctuation and capitalization.
2. Remove fillers ("um", "uh", "like", "matlab" used as filler, "you know")
   and false starts.
3. Resolve ONLY clear self-corrections, keeping the speaker's final choice.
4. Never add information. Never change numbers, names, amounts, dates,
   URLs, emails, or code identifiers.
5. Never translate. Preserve the exact mix of English and Hindi words.
6. If unsure whether something is a correction, leave it unchanged.
7. Return only the edited text. No preamble, no quotes, no explanation.

Examples:

Input: um so can we meet on tuesday scratch that i think wednesday is better
Output: Can we meet on Wednesday? I think that works better.

Input: bhai woh invoice bhej dena aaj sorry kal tak chalega
Output: Bhai woh invoice kal tak bhej dena, chalega.

Input: send ten thousand no wait one thousand rupees to ramesh
Output: Send ₹1,000 to Ramesh.

Input: meeting ko postpone kar do matlab i mean thursday ko rakh lo
Output: Meeting ko Thursday ko rakh lo.

Input: i actually enjoyed the movie it was really good
Output: I actually enjoyed the movie. It was really good.

Input: deployment ready hai kya check karo and phir mujhe ping karna
Output: Deployment ready hai kya, check karo, and phir mujhe ping karna.

Input: uh the pr link is github dot com slash niyo slash payments okay review it
Output: The PR link is github.com/niyo/payments. Review it.

Input: haan theek hai kal milte hain
Output: Haan, theek hai. Kal milte hain.
```

Notes on the examples:
- Example 3 shows number correction resolution — and is exactly the case the validator double-checks.
- Example 5 is the **restraint** example: "actually" is not a correction cue.
- Example 8 is a simple utterance that the fast-path classifier should have caught anyway — it's in the prompt as a safety net so the LLM does no harm if routing ever misfires.
- Grow this set from flywheel data (D7). Six pairs is the launch minimum; ten is the target.

**Context-aware variant:** when the foreground app is known, prepend one line — `The text will be inserted into {app_name}. Match the register typical for that app.` — and add one Slack-casual and one email-structured example pair in `cleanup-v1-context.txt`.

---

# Part IV — Benchmarks and gates

## Golden-test suites (all mandatory, all runnable offline in CI)

1. **ASR — English:** Indian + US accents, fast speech, fan/café noise, technical terms.
2. **ASR — Hinglish:** mostly-English-with-Hindi, mostly-Hindi-with-English, product names (Niyo, Oynix, Neo4j), Indian names and places, Roman output.
3. **Cleanup — corrections:** "Friday sorry Monday", currency corrections, "nahi nahi" patterns, false starts, spoken lists, email requests.
4. **Cleanup — restraint:** utterances containing "actually", "sorry" as apology (not correction), rhetorical repetition — all must pass through **unchanged**.
5. **Validator red-team:** adversarial LLM outputs that alter a number, drop a name, translate a clause, or invent a claim — validator must catch 100%.
6. **Hallucination-on-silence, Hinglish-specific:** Whisper's silence hallucinations in Hindi contexts produce distinctive garbage — repeated devotional phrases, YouTube-outro boilerplate ("like share subscribe"), repeated tokens. These are explicit regression fixtures, not generic silence tests.

## Metrics

- ASR: WER (English), code-switch error rate (custom), entity accuracy, number accuracy, hallucination rate, RTF, peak RAM, cold + warm latency.
- Cleanup: correction accuracy, meaning preservation, protected-token preservation (must be 100% post-validator), language preservation, restraint pass rate, human rating.
- End-to-end: shortcut-release → text-inserted, p50 and p95, per hardware tier.

## Promotion gates (a model becomes default only when ALL pass)

accuracy threshold · p95 release-to-insert < 1 s warm on the mid tier · RAM ceiling per tier · crash-free · **license + provenance review (before benchmarking, per D2)** · offline packaging test.

## Hardware matrix

macOS: M1 8 GB · M1/M2 16 GB · M3/M4 16 GB+ · Intel Mac (x86_64, no AVX assumption).
Windows: modern Intel iGPU-only · AMD iGPU-only · NVIDIA laptop · 8 GB and 16 GB RAM · Windows 10 1809 baseline.

---

# Part V — Footprint budget (V1)

| Component | Size | Notes |
|---|---|---|
| App shell (Flutter + Rust core) | ~60–150 MB | vs Wispr's ~800 MB idle Electron RAM |
| Silero VAD (ggml) | ~2 MB | via whisper.cpp |
| swar Balanced — Whisper small int8, Hindi-tuned | ~200 MB | default, always warm |
| Cleanup LLM — 1.7B Q4 *(pending D4 benchmark)* | ~1 GB | routed, not always resident |
| **Core install** | **~1.3 GB** | fully offline |
| Optional: swar Accurate (turbo int8) | +500 MB | opt-in pack |
| Optional: 3B cleanup pack *(if D4 says so)* | +1 GB | "better cleanup" opt-in |
| Optional: swar Lite (base int8) | +75 MB | old hardware |

Positioning line: *Wispr idles at ~800 MB of RAM and still needs the cloud for every keystroke. swar's ~1.3 GB lives on disk, loads on demand, and works with no internet at all.*

---

# Part VI — Deferred (explicitly out of V1)

- **Command Mode** ("make the last line more concise") → V1.1. Good feature, but content-vs-instruction routing is genuinely hard and it violates the V1 scope rules (Dictation, Insights, General, System — nothing else).
- **Qwen3-ASR / IndicConformer** → Phase 11 bake-off candidates behind the `AsrEngine` trait; never a V1 hard dependency.
- **Cloud model mode, accounts, teams, encrypted DB** → later, threat-modeled first.

---

# Part VII — Amendments to the Build Plan phases

The Build Plan's Phases 0–12 stand, with these edits:

- **Phase 4 (Offline ASR):** default model is the Hindi-fine-tuned *small* int8 (D2). Add Silero VAD via whisper.cpp here, not later. Add the Hinglish hallucination fixtures to acceptance.
- **Phase 7 (Text insertion):** add an **undo-semantics matrix** to acceptance — Cmd+Z / Ctrl+Z behavior after AX/UIA insertion vs paste, per app in the compatibility list. Users hit this in week one; at minimum document per-app behavior, at best pick the insertion method per app that yields a single undo step.
- **Phase 9 (Clean mode):** add the fast-path classifier here (it gates Phase 10), plus the restraint golden suite.
- **Phase 10 (Intent mode):** llama.cpp embedded only (D6). Ship `cleanup-v1.txt` as a versioned artifact with golden tests. Validator red-team suite is an acceptance gate. Add the D4 1.7B-vs-3B benchmark as the phase's exit decision.
- **New Phase 10.5 — Flywheel + LoRA:** opt-in correction-triple export (D7); LoRA fine-tune experiment of the smaller model on Hinglish pairs; promote via the standard gates.
- **Phase 11 (Bake-off):** license/provenance review moves to the *entry* criteria, not exit (D2).
- **State machine (Phase 5/18):** apply the pipelining amendment (Part II) — recording may start while the previous session is post-Finalising.

## Additions to AGENTS.md

```md
21. The cleanup system prompt is a versioned artifact; changes require the
    cleanup golden suite (corrections + restraint + validator red-team) to pass.
22. LLM cleanup runs only via the fast-path classifier routing rules; never
    unconditionally.
23. The protected-token validator gates every LLM rewrite. No bypass flag.
24. Foreground app names may be passed to prompts at runtime but never
    persisted, and must honor the excluded-apps list.
25. Model licenses and training-data provenance are reviewed before a model
    enters benchmarking.
26. No model load may occur between shortcut release and insertion on the
    warm path.
```

---

# Part VIII — One-page summary

**swar V1** = English + Hindi + Hinglish, local by default. Warm quantized Whisper model packs stream partials while you speak. Deterministic cleanup always; routed enhancement is protected by a validator that rejects unexplained changes to numbers, names, negation, or language. Silero VAD, no account, no audio stored, and opt-in local learning remain hard requirements.

The loop to perfect before anything else:

```text
click field → hold shortcut → speak → release → text appears → history updates → insights update
```

Everything else waits until that loop is boringly reliable.
