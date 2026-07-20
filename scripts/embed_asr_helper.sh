#!/usr/bin/env sh
# Builds the fast offline ASR helper (`swar_asr_server`) and embeds it, together
# with its ONNX runtime dylibs, in the macOS app bundle at Contents/MacOS/, where
# the app locates it at runtime (a sibling of the main executable). The helper
# hosts the two ONNX speech engines (Parakeet + IndicConformer) out of process, so
# no ONNX runtime ever links into the app framework. Run after
# `flutter build macos --release` and before signing. Idempotent.
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
    echo "Rust cargo was not found; cannot build the ASR helper." >&2
    exit 1
  fi
  PATH=$(dirname "$cargo_bin"):$PATH
  export PATH
fi

arm_target=aarch64-apple-darwin
x86_target=x86_64-apple-darwin
macos_dir="$app_path/Contents/MacOS"
dest="$macos_dir/swar_asr_server"

echo "Building swar_asr_server ($arm_target)..."
cargo build -p swar_asr_server --release --target "$arm_target" --manifest-path "$repo_dir/Cargo.toml"

arm_bin="$repo_dir/target/$arm_target/release/swar_asr_server"
x86_bin="$repo_dir/target/$x86_target/release/swar_asr_server"

# The Intel slice keeps the helper universal to match the app. sherpa-onnx and
# onnxruntime binaries are unavailable for every host, so fall back to an
# arm64-only helper when the Intel cross-build fails (Intel Macs then use whisper).
if cargo build -p swar_asr_server --release --target "$x86_target" --manifest-path "$repo_dir/Cargo.toml" 2>/dev/null \
  && [ -f "$x86_bin" ]; then
  echo "Creating universal ASR helper (arm64 + x86_64)..."
  lipo -create "$arm_bin" "$x86_bin" -output "$dest"
else
  echo "WARNING: x86_64 ASR helper unavailable; embedding arm64-only helper." >&2
  cp "$arm_bin" "$dest"
fi
chmod +x "$dest"

# The helper references its ONNX dylibs by @rpath. sherpa-rs ships them universal
# (arm64 + x86_64), so copy the versioned onnxruntime and the sherpa C API from
# the native release dir beside the helper. libsherpa-onnx-c-api itself references
# @rpath/libonnxruntime, so both need @loader_path on their rpath.
dylib_src="$repo_dir/target/release"
if [ ! -f "$dylib_src/libonnxruntime.1.17.1.dylib" ]; then
  echo "Building native ASR dylibs (for the universal onnxruntime/sherpa libs)..."
  cargo build -p swar_asr_server --release --manifest-path "$repo_dir/Cargo.toml" >/dev/null
fi

for lib in libonnxruntime.1.17.1.dylib libsherpa-onnx-c-api.dylib; do
  if [ ! -f "$dylib_src/$lib" ]; then
    echo "Required ASR dylib missing: $dylib_src/$lib" >&2
    exit 1
  fi
  cp "$dylib_src/$lib" "$macos_dir/$lib"
done

# Add @loader_path so @rpath/... resolves to the sibling dylibs without relying on
# DYLD_LIBRARY_PATH (belt and suspenders: asr_client also sets it). Ignore errors
# if the rpath already exists from a previous run.
install_name_tool -add_rpath "@loader_path" "$dest" 2>/dev/null || true
install_name_tool -add_rpath "@loader_path" "$macos_dir/libsherpa-onnx-c-api.dylib" 2>/dev/null || true

echo "Embedded ASR helper at: $dest"
lipo -info "$dest"
echo "Bundled ASR dylibs:"
ls -1 "$macos_dir"/libonnxruntime.1.17.1.dylib "$macos_dir"/libsherpa-onnx-c-api.dylib
