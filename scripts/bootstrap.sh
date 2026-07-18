#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir/apps/swar_desktop"
flutter pub get
cd "$repo_dir"
./scripts/generate_bridge.sh

