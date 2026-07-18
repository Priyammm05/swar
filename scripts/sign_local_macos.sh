#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_dir/apps/swar_desktop/build/macos/Build/Products/Release/swar.app"}

if [ ! -d "$app_path" ]; then
  echo "Swar app bundle not found: $app_path" >&2
  exit 1
fi

# Sign nested code first so the outer app seal records its final signatures.
# Giving the custom requirement only to the app keeps framework identities
# independent while Swar retains one stable Accessibility identity.
for framework in "$app_path"/Contents/Frameworks/*.framework; do
  codesign --force --sign - "$framework"
done

# A plain ad-hoc app signature uses the executable hash as its identity, which
# makes macOS Accessibility permission expire after every local rebuild. This
# stable designated requirement keeps local builds associated with Swar.
codesign --force --sign - \
  --requirements '=designated => identifier "dev.swar.desktop"' \
  "$app_path"
codesign --verify --deep --strict "$app_path"
