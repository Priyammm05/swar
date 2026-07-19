#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
model_path=${SWAR_ASR_MODEL_PATH:-"$HOME/Library/Application Support/dev.Swar.Swar/models/ggml-small-q5_1.bin"}

if [ ! -f "$model_path" ]; then
  echo "Install the Swar offline model first or set SWAR_ASR_MODEL_PATH." >&2
  exit 1
fi

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/swar-asr-benchmark.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

make_fixture() {
  voice=$1
  text_file=$2
  wav_file=$3
  aiff_file="$fixture_dir/source.aiff"
  say -v "$voice" -f "$text_file" -o "$aiff_file"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$aiff_file" "$wav_file"
}

run_case() {
  case_id=$1
  language=$2
  voice=$3
  case_file=$4
  maximum_wer=$5
  maximum_rtf=$6
  wav_file="$fixture_dir/$case_id.wav"
  make_fixture "$voice" "$case_file" "$wav_file"
  SWAR_BENCHMARK_MAX_WER="$maximum_wer" \
  SWAR_BENCHMARK_MAX_RTF="$maximum_rtf" \
    cargo run --quiet -p swar_core --bin swar_asr_benchmark -- \
    "$model_path" "$wav_file" "$language" "$case_file"
}

case "$(uname -s)" in
  Darwin)
    run_case english-long english Aman "$repo_dir/benchmark/cases/english-01.txt" 0.35 1.0
    run_case hindi-long hindi Lekha "$repo_dir/benchmark/cases/hindi-01.txt" 0.55 1.0
    run_case hinglish-long hinglish Aman "$repo_dir/benchmark/cases/hinglish-01.txt" 0.30 1.0
    # Short speech caught a production regression where detect_language=true
    # returned after detection without decoding any transcript segments.
    run_case automatic-english-short automatic Aman "$repo_dir/benchmark/cases/english-short.txt" 0.35 1.8
    run_case automatic-hindi-short automatic Lekha "$repo_dir/benchmark/cases/hindi-short.txt" 0.55 1.8
    run_case hinglish-short hinglish Lekha "$repo_dir/benchmark/cases/hinglish-short.txt" 0.55 1.8
    ;;
  *)
    echo "Synthetic ASR fixtures currently require the macOS say and afconvert tools." >&2
    exit 2
    ;;
esac
