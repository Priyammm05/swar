#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
iterations=${1:-10000}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output="$repo_dir/benchmark/reports/generated/pipeline-$stamp.json"

if ! command -v cargo >/dev/null 2>&1; then
  cargo_bin=$(find "$HOME/.rustup/toolchains" -path '*/bin/cargo' -type f | sort | head -n 1)
  if [ -z "$cargo_bin" ]; then
    echo "Rust cargo was not found." >&2
    exit 1
  fi
  PATH=$(dirname "$cargo_bin"):$PATH
  export PATH
fi

mkdir -p "$(dirname "$output")"
cargo run --quiet --release --manifest-path "$repo_dir/Cargo.toml" \
  --bin swar_text_benchmark -- "$iterations" > "$output"
cat "$output"
echo "$output"
