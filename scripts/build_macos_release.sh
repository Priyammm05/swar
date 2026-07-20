#!/usr/bin/env sh
# One command for a complete, ready-to-install macOS release: it builds the
# Flutter app, embeds the universal offline cleanup helper (swar_llm_server),
# signs the bundle with Swar's stable local Accessibility identity, and verifies
# the result. Use this rather than a bare `flutter build macos` so the shipped
# app always contains the cleanup helper.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Put the project's Flutter SDK on PATH (recorded by `flutter pub get`).
xcconfig="$repo_dir/apps/swar_desktop/macos/Flutter/ephemeral/Flutter-Generated.xcconfig"
if [ -f "$xcconfig" ]; then
  flutter_root=$(grep -m1 '^FLUTTER_ROOT=' "$xcconfig" | cut -d= -f2)
  if [ -n "${flutter_root:-}" ] && [ -x "$flutter_root/bin/flutter" ]; then
    PATH="$flutter_root/bin:$PATH"
    export PATH
  fi
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter was not found on PATH and FLUTTER_ROOT could not be resolved." >&2
  exit 1
fi

# `common` (llama.cpp's httplib downloader) must stay off for the helper link.
export LLAMA_BUILD_COMMON=OFF
export LLAMA_CURL=OFF

echo "==> flutter build macos --release"
( cd "$repo_dir/apps/swar_desktop" && flutter build macos --release )

echo "==> embedding the offline cleanup helper"
"$repo_dir/scripts/embed_llm_helper.sh"

echo "==> embedding the fast ASR helper and its ONNX dylibs"
"$repo_dir/scripts/embed_asr_helper.sh"

echo "==> signing with the stable local Accessibility identity"
"$repo_dir/scripts/sign_local_macos.sh"

echo "==> verifying the bundle"
"$repo_dir/scripts/verify_macos_bundle.sh"

echo "Release build ready: the app bundle contains a signed offline cleanup helper."
