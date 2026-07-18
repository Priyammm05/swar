#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
presentation_root="$project_root/apps/swar_desktop/lib"

violations=$(
  find "$presentation_root" -type f -path '*/presentation/*.dart' \
    -exec grep -nH 'generated_bridge' {} + 2>/dev/null || true
)

if [ -n "$violations" ]; then
  echo "Flutter presentation code must not import the generated Rust bridge." >&2
  echo "$violations" >&2
  exit 1
fi

echo "Verified Flutter presentation and Rust bridge boundaries."
