#!/usr/bin/env sh
set -eu

if [ "$#" -ne 5 ]; then
  echo "usage: $0 REFERENCE SWAR_TRANSCRIPT WISPR_TRANSCRIPT SWAR_LATENCY_MS WISPR_LATENCY_MS" >&2
  exit 2
fi

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output="$repo_dir/benchmark/reports/generated/$stamp.json"

python3 "$repo_dir/benchmark/compare_transcripts.py" \
  "$1" "$2" "$3" "$4" "$5" "$output"

echo "$output"
