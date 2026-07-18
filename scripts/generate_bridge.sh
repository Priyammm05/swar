#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml

