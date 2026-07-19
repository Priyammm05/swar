#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-fast}

case "$mode" in
  fast|full) ;;
  *)
    echo "usage: $0 [fast|full]" >&2
    exit 2
    ;;
esac

unset GITHUB_TOKEN GH_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY

if ! command -v cargo >/dev/null 2>&1; then
  cargo_bin=$(find "$HOME/.rustup/toolchains" -path '*/bin/cargo' -type f | sort | head -n 1)
  if [ -z "$cargo_bin" ]; then
    echo "Rust cargo was not found." >&2
    exit 1
  fi
  PATH=$(dirname "$cargo_bin"):$PATH
fi

if ! command -v flutter >/dev/null 2>&1; then
  flutter_root=$(sed -n 's/^FLUTTER_ROOT=//p' \
    "$repo_dir/apps/swar_desktop/macos/Flutter/ephemeral/Flutter-Generated.xcconfig" | head -n 1)
  if [ -z "$flutter_root" ] || [ ! -x "$flutter_root/bin/flutter" ]; then
    echo "Flutter was not found." >&2
    exit 1
  fi
  PATH=$flutter_root/bin:$PATH
fi
export PATH
export FLUTTER_SUPPRESS_ANALYTICS=true

if ! command -v rustup >/dev/null 2>&1; then
  PATH=$repo_dir/scripts/toolchain_shims:$PATH
  export PATH
fi

cd "$repo_dir"
cargo fmt --all -- --check
cargo check --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --all-targets
./scripts/verify_flutter_boundaries.sh
./scripts/verify_user_testing_framework.sh

cd "$repo_dir/apps/swar_desktop"
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test

if [ "$mode" = full ]; then
  cd "$repo_dir"
  ./scripts/run_pipeline_microbenchmark.sh 10000

  cd "$repo_dir/apps/swar_desktop"
  case "$(uname -s)" in
    Darwin)
      "$repo_dir/scripts/run_asr_benchmark_suite.sh"
      flutter test integration_test/core_bridge_test.dart -d macos
      "$repo_dir/scripts/run_synthetic_user_test.sh" macos
      ;;
    MINGW*|MSYS*|CYGWIN*)
      flutter test integration_test/core_bridge_test.dart -d windows
      "$repo_dir/scripts/run_synthetic_user_test.sh" windows
      ;;
    *)
      echo "Full desktop integration requires macOS or Windows." >&2
      exit 1
      ;;
  esac
fi

echo "Swar $mode test framework passed."
