#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
target=${1:-}

if [ -z "$target" ]; then
  case "$(uname -s)" in
    Darwin) target=macos ;;
    MINGW*|MSYS*|CYGWIN*) target=windows ;;
    *)
      echo "Pass a desktop target: macos or windows" >&2
      exit 2
      ;;
  esac
fi

case "$target" in
  macos|windows) ;;
  *)
    echo "Unsupported synthetic-user target: $target" >&2
    exit 2
    ;;
esac

cd "$project_root/apps/swar_desktop"

# Product builds never need developer service credentials. Keep them out of
# Xcode/MSBuild child processes and their diagnostic logs.
unset GITHUB_TOKEN GH_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY

run_log=$(mktemp "${TMPDIR:-/tmp}/swar-synthetic-user.XXXXXX")
trap 'rm -f "$run_log"' EXIT HUP INT TERM

run_status=0
flutter test \
  integration_test/synthetic_user_journey_test.dart \
  -d "$target" > "$run_log" 2>&1 || run_status=$?

cat "$run_log"

if [ "$run_status" -ne 0 ]; then
  exit "$run_status"
fi

if grep -Eq 'Unhandled Exception:|Some tests failed|Test failed\. See exception|This test failed after it had already completed' "$run_log"; then
  echo "Synthetic-user run produced an error that Flutter did not return as a failing exit code." >&2
  exit 1
fi

evidence_path=$(sed -n 's/^.*SWAR_SYNTHETIC_USER_EVIDENCE=//p' "$run_log" | tail -n 1)
if [ -n "$evidence_path" ] && command -v cygpath >/dev/null 2>&1; then
  evidence_path=$(cygpath -u "$evidence_path")
fi

if [ -z "$evidence_path" ] || [ ! -d "$evidence_path" ]; then
  echo "Synthetic-user test passed without producing an evidence directory." >&2
  exit 1
fi

output_path="$project_root/apps/swar_desktop/build/user-testing/synthetic-user"
mkdir -p "$output_path"
cp -R "$evidence_path/." "$output_path"

echo "Synthetic-user evidence: apps/swar_desktop/build/user-testing/synthetic-user"
