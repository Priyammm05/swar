#!/usr/bin/env sh
set -eu

bundle_path=${1:-apps/swar_desktop/build/macos/Build/Products/Release/swar.app}
executable="$bundle_path/Contents/MacOS/swar"

if [ ! -f "$executable" ]; then
  echo "Missing macOS executable: $executable" >&2
  exit 1
fi

verify_universal_binary() {
  binary=$1
  label=$2
  architectures=$(lipo -archs "$binary")

  case " $architectures " in
    *" arm64 "*) ;;
    *)
      echo "$label is missing the arm64 slice: $architectures" >&2
      exit 1
      ;;
  esac

  case " $architectures " in
    *" x86_64 "*) ;;
    *)
      echo "$label is missing the x86_64 slice: $architectures" >&2
      exit 1
      ;;
  esac

  echo "Verified Universal 2 $label: $architectures"
}

verify_universal_binary "$executable" "application executable"

for framework in "$bundle_path"/Contents/Frameworks/*.framework; do
  framework_name=$(basename "$framework" .framework)
  framework_executable="$framework/$framework_name"
  if [ ! -f "$framework_executable" ]; then
    framework_executable="$framework/Versions/A/$framework_name"
  fi
  if [ ! -f "$framework_executable" ]; then
    echo "Missing framework executable for $framework_name" >&2
    exit 1
  fi
  verify_universal_binary "$framework_executable" "$framework_name.framework"
done

info_plist="$bundle_path/Contents/Info.plist"
minimum_version=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")
if [ "$minimum_version" != "10.15" ]; then
  echo "Expected macOS 10.15 minimum, found $minimum_version" >&2
  exit 1
fi

microphone_usage=$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$info_plist")
if [ -z "$microphone_usage" ]; then
  echo "The release bundle is missing its microphone usage description." >&2
  exit 1
fi

echo "Verified macOS 10.15 deployment target and microphone privacy metadata."
