#!/usr/bin/env sh
# Builds the offline cleanup helper (`swar_llm_server`) as a universal binary and
# embeds it in the macOS app bundle at Contents/MacOS/swar_llm_server, where the
# app locates it at runtime (a sibling of the main executable). Run after
# `flutter build macos --release` and before signing. Idempotent: cargo builds
# incrementally, so repeat runs are cheap.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_dir/apps/swar_desktop/build/macos/Build/Products/Release/swar.app"}

if [ ! -d "$app_path" ]; then
  echo "Swar app bundle not found: $app_path" >&2
  exit 1
fi

# cargokit does not put cargo on PATH for arbitrary scripts; discover it the same
# way scripts/run_test_framework.sh does.
if ! command -v cargo >/dev/null 2>&1; then
  cargo_bin=$(find "$HOME/.rustup/toolchains" -path '*/bin/cargo' -type f | sort | head -n 1)
  if [ -z "$cargo_bin" ]; then
    echo "Rust cargo was not found; cannot build the cleanup helper." >&2
    exit 1
  fi
  PATH=$(dirname "$cargo_bin"):$PATH
  export PATH
fi

# `common` (llama.cpp's httplib downloader) never links in our build; keep it off.
export LLAMA_BUILD_COMMON=OFF
export LLAMA_CURL=OFF

arm_target=aarch64-apple-darwin
x86_target=x86_64-apple-darwin

echo "Building swar_llm_server ($arm_target)..."
cargo build -p swar_llm_server --release --target "$arm_target" --manifest-path "$repo_dir/Cargo.toml"

arm_bin="$repo_dir/target/$arm_target/release/swar_llm_server"
x86_bin="$repo_dir/target/$x86_target/release/swar_llm_server"
dest="$app_path/Contents/MacOS/swar_llm_server"

# The Intel slice keeps the helper universal to match the app. If its toolchain
# or llama.cpp cross-build is unavailable, fall back to an arm64-only helper so
# the build still succeeds (Intel Macs then use deterministic cleanup).
if cargo build -p swar_llm_server --release --target "$x86_target" --manifest-path "$repo_dir/Cargo.toml" 2>/dev/null \
  && [ -f "$x86_bin" ]; then
  echo "Creating universal helper (arm64 + x86_64)..."
  lipo -create "$arm_bin" "$x86_bin" -output "$dest"
else
  echo "WARNING: x86_64 helper unavailable; embedding arm64-only helper." >&2
  cp "$arm_bin" "$dest"
fi

chmod +x "$dest"
echo "Embedded cleanup helper at: $dest"
lipo -info "$dest"
