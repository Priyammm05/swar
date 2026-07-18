#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_icon_source="$project_root/apps/logo/svar_logo_large_green_centered.svg"
menu_icon_source="$project_root/apps/logo/svar_logo_mark_black_centered.svg"
mac_app_icon_dir="$project_root/apps/swar_desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mac_menu_icon_dir="$project_root/apps/swar_desktop/macos/Runner/Assets.xcassets/MenuBarIcon.imageset"
windows_icon="$project_root/apps/swar_desktop/windows/runner/resources/app_icon.ico"

for command_name in rsvg-convert ffmpeg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

for size in 16 32 64 128 256 512 1024; do
  rsvg-convert \
    -w "$size" \
    -h "$size" \
    "$app_icon_source" \
    -o "$mac_app_icon_dir/app_icon_${size}.png"
done

rsvg-convert -w 41 -h 15 "$menu_icon_source" -o "$mac_menu_icon_dir/menu_bar_icon.png"
rsvg-convert -w 82 -h 30 "$menu_icon_source" -o "$mac_menu_icon_dir/menu_bar_icon@2x.png"

icon_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/swar-icons.XXXXXX")
trap 'rm -rf "$icon_work_dir"' EXIT HUP INT TERM

for size in 16 24 32 48 64 128 256; do
  rsvg-convert \
    -w "$size" \
    -h "$size" \
    "$app_icon_source" \
    -o "$icon_work_dir/app_icon_${size}.png"
done

ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -i "$icon_work_dir/app_icon_16.png" \
  -i "$icon_work_dir/app_icon_24.png" \
  -i "$icon_work_dir/app_icon_32.png" \
  -i "$icon_work_dir/app_icon_48.png" \
  -i "$icon_work_dir/app_icon_64.png" \
  -i "$icon_work_dir/app_icon_128.png" \
  -i "$icon_work_dir/app_icon_256.png" \
  -map 0:v \
  -map 1:v \
  -map 2:v \
  -map 3:v \
  -map 4:v \
  -map 5:v \
  -map 6:v \
  -c:v png \
  -pix_fmt rgba \
  "$windows_icon"

echo "Generated macOS and Windows icons."
