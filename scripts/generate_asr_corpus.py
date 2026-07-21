#!/usr/bin/env python3
"""Builds a saved, reproducible English dictation corpus for ASR scoring.

Two properties matter more than anything else here.

**The fixtures are written once and kept.** `run_asr_benchmark_suite.sh`
synthesises its audio with `say` on every run, so two runs of identical code
compare different recordings; the same case has scored 0.118, 0.176, 0.382 and
0.809 across runs. Any comparison between two builds has to hold the audio fixed.

**Lengths are stratified, not log-uniform.** Real dictation is mostly short with
a long tail, and the failures found so far were length-dependent: whisper
corrupts its own 30 s window seam, which no short fixture can catch. Stratifying
guarantees every bucket is populated instead of leaving coverage to chance, and
it keeps the corpus inside a decode budget — drawing 1000 cases log-uniformly
over 20..2000 averages 430 words and costs about five hours to score, where the
strata below average 153 and finish in under two.

Usage:
    generate_asr_corpus.py OUTPUT_DIR [--cases 1000] [--seed 7]
"""

import argparse
import json
import pathlib
import random
import subprocess
import sys

# Dictation-shaped material: plain prose, technical talk, numbers, addresses and
# proper nouns. Recognition failures cluster in the last three, so they are not
# left to chance.
OPENERS = [
    "So basically the way I am thinking about this is that",
    "Quick note before I forget,",
    "Can you take a look at this when you get a chance,",
    "I spoke to the team this morning and",
    "Just following up on yesterday's conversation,",
    "Here is where we landed after the review,",
    "Reminder for tomorrow,",
    "I have been going back and forth on this but",
]
CLAUSES = [
    "we need to ship the prototype first and see how it performs under real load",
    "the indexing is going to be the hardest part because every user has different data",
    "we should measure the latency before we add any more connectors to the pipeline",
    "the pricing has to feel affordable for small teams while still working for large accounts",
    "I would rather keep the scope narrow and get it correct than build all of it badly",
    "the migration touches about forty files so it needs a proper review",
    "we can cache the embeddings and avoid recomputing them on every single request",
    "the current approach falls over as soon as the payload gets larger than a few megabytes",
    "it might be worth writing a small benchmark before committing to either design",
    "the retry logic masks the real failure so the logs never show what actually broke",
    "we agreed to revisit this once the numbers come back from the pilot",
    "there is no point optimising that path until we know it is actually hot",
]
TECHNICAL = [
    "the Kafka consumer is dropping messages when the partition rebalances",
    "the Postgres query plan changed after the index was rebuilt",
    "we should pin the Docker image rather than tracking latest",
    "the gRPC timeout is set to thirty seconds which is far too generous",
    "the React component re-renders on every keystroke because the prop is a new object",
    "the S3 bucket policy is blocking the presigned URL from the staging environment",
    "the Redis connection pool exhausts under concurrent writes",
    "the CI pipeline fails intermittently on the integration test suite",
]
FACTUAL = [
    "the total came to forty two thousand five hundred rupees",
    "the meeting is at ten thirty on Tuesday the fourteenth",
    "send it to priya dot sharma at example dot com",
    "the invoice number is INV 2024 0918",
    "we are tracking this in JIRA ticket PLAT 4471",
    "the deadline moved from March third to March seventeenth",
    "it went from ninety eight percent to sixty four percent overnight",
    "the API key rotates every ninety days",
]
CLOSERS = [
    "Let me know what you think.",
    "Happy to discuss if that does not make sense.",
    "I will pick this up again tomorrow morning.",
    "Flag it if you disagree.",
    "That is everything from my side.",
]


# (share of cases, minimum words, maximum words). Weighted toward short
# utterances because that is what dictation mostly is, while still guaranteeing
# cases either side of whisper's 30 s window (~75 words at 150 wpm) and a real
# long tail out to 2000 words.
STRATA = [
    (0.42, 20, 50),
    (0.32, 50, 150),
    (0.18, 150, 400),
    (0.06, 400, 900),
    (0.02, 900, 2000),
]


def target_lengths(rng, cases):
    """One target word count per case, drawn stratum by stratum."""
    lengths = []
    for share, low, high in STRATA:
        for _ in range(round(share * cases)):
            lengths.append(rng.randint(low, high))
    # Rounding can leave the total a case or two short of the request.
    while len(lengths) < cases:
        lengths.append(rng.randint(STRATA[0][1], STRATA[0][2]))
    rng.shuffle(lengths)
    return lengths[:cases]


def build_text(rng, target_words):
    """Composes a passage of roughly `target_words`, mixing all four registers."""
    parts = [rng.choice(OPENERS)]
    count = len(parts[0].split())
    pools = [CLAUSES, CLAUSES, TECHNICAL, FACTUAL]
    while count < target_words:
        piece = rng.choice(rng.choice(pools))
        parts.append(piece + rng.choice([".", ".", ",", " and"]))
        count += len(piece.split())
    parts.append(rng.choice(CLOSERS))
    text = " ".join(parts)
    text = text.replace(" ,", ",").replace(" .", ".").replace("..", ".")
    return text


def synthesise(text, aiff, wav, voice, rate):
    subprocess.run(
        ["say", "-v", voice, "-r", str(rate), "-o", str(aiff), text],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)],
        check=True,
        capture_output=True,
    )
    aiff.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--voice", default="Samantha")
    parser.add_argument("--rate", type=int, default=175)
    args = parser.parse_args()

    out = pathlib.Path(args.output)
    (out / "wav").mkdir(parents=True, exist_ok=True)
    (out / "text").mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)

    manifest = out / "manifest.jsonl"
    written, total_words = 0, 0
    lengths = target_lengths(rng, args.cases)
    with manifest.open("w") as handle:
        for index, target in enumerate(lengths):
            text = build_text(rng, target)
            case_id = f"case{index:04d}"
            text_path = out / "text" / f"{case_id}.txt"
            wav_path = out / "wav" / f"{case_id}.wav"
            text_path.write_text(text + "\n")
            if not wav_path.exists():
                try:
                    synthesise(
                        text, out / f"{case_id}.aiff", wav_path, args.voice, args.rate
                    )
                except subprocess.CalledProcessError as error:
                    print(f"{case_id}: synthesis failed: {error}", file=sys.stderr)
                    continue
            words = len(text.split())
            total_words += words
            written += 1
            handle.write(
                json.dumps(
                    {
                        "id": case_id,
                        "words": words,
                        "wav": str(wav_path),
                        "text": str(text_path),
                    }
                )
                + "\n"
            )
            if written % 50 == 0:
                print(f"  {written}/{args.cases} cases", file=sys.stderr, flush=True)

    print(f"wrote {written} cases, {total_words:,} words -> {manifest}")


if __name__ == "__main__":
    main()
