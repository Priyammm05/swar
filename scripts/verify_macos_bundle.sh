#!/usr/bin/env sh
set -eu

bundle_path=${1:-apps/swar_desktop/build/macos/Build/Products/Release/swar_desktop.app}
executable="$bundle_path/Contents/MacOS/swar_desktop"

if [ ! -f "$executable" ]; then
  echo "Missing macOS executable: $executable" >&2
  exit 1
fi

architectures=$(lipo -archs "$executable")

case " $architectures " in
  *" arm64 "*) ;;
  *)
    echo "macOS application is missing the arm64 slice: $architectures" >&2
    exit 1
    ;;
esac

case " $architectures " in
  *" x86_64 "*) ;;
  *)
    echo "macOS application is missing the x86_64 slice: $architectures" >&2
    exit 1
    ;;
esac

echo "Verified Universal 2 executable: $architectures"
