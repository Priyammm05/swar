#!/usr/bin/env python3
import json
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).lower()
    value = re.sub(r"[^\w\s]", " ", value, flags=re.UNICODE)
    return " ".join(value.split())


def distance(left, right):
    previous = list(range(len(right) + 1))
    for row, left_item in enumerate(left, 1):
        current = [row]
        for column, right_item in enumerate(right, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (left_item != right_item),
                )
            )
        previous = current
    return previous[-1]


def score(reference: str, candidate: str, latency_ms: int):
    reference_normalized = normalize(reference)
    candidate_normalized = normalize(candidate)
    reference_words = reference_normalized.split()
    candidate_words = candidate_normalized.split()
    word_errors = distance(reference_words, candidate_words)
    character_errors = distance(reference_normalized, candidate_normalized)
    return {
        "word_error_rate": round(word_errors / max(1, len(reference_words)), 4),
        "character_error_rate": round(
            character_errors / max(1, len(reference_normalized)), 4
        ),
        "reference_words": len(reference_words),
        "candidate_words": len(candidate_words),
        "completion_latency_ms": latency_ms,
    }


def main():
    if len(sys.argv) != 7:
        raise SystemExit(
            "usage: compare_transcripts.py REFERENCE SWAR WISPR SWAR_MS WISPR_MS OUTPUT"
        )
    reference_path, swar_path, wispr_path = map(Path, sys.argv[1:4])
    swar_ms, wispr_ms = map(int, sys.argv[4:6])
    output_path = Path(sys.argv[6])
    reference = reference_path.read_text(encoding="utf-8")
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "reference": str(reference_path),
        "method": "same scripted passage, separate live dictations",
        "swar": score(reference, swar_path.read_text(encoding="utf-8"), swar_ms),
        "wispr_flow": score(
            reference, wispr_path.read_text(encoding="utf-8"), wispr_ms
        ),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
