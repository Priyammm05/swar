#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$project_root/quality/user-testing/scenarios/manifest.txt"
template="$project_root/quality/user-testing/templates/session.md"
plan_name=${1:-}

if [ -z "$plan_name" ]; then
  echo "Usage: ./scripts/start_user_test.sh PLAN_NAME" >&2
  echo "Available plans:" >&2
  sed -n 's/^\([^#][^|]*\)|.*$/  \1/p' "$manifest" >&2
  exit 2
fi

case "$plan_name" in
  *[!a-z0-9-]*|'')
    echo "Invalid plan name: $plan_name" >&2
    exit 2
    ;;
esac

scenario_path=$(awk -F '|' -v plan="$plan_name" '$1 == plan { print $2 }' "$manifest")
if [ -z "$scenario_path" ]; then
  echo "Unknown plan: $plan_name" >&2
  exit 2
fi

scenario_file="$project_root/$scenario_path"
if [ ! -f "$scenario_file" ]; then
  echo "Scenario file is missing: $scenario_path" >&2
  exit 1
fi

session_root=${SWAR_USER_TEST_DIR:-"$project_root/.user-testing/sessions"}
session_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
session_file="$session_root/${session_stamp}-${plan_name}.md"
mkdir -p "$session_root"

{
  echo "# Swar user test: $plan_name"
  echo
  echo "- Started UTC: $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "- Host: $(uname -s) $(uname -m)"
  echo "- Scenario source: $scenario_path"
  echo
  sed '1d' "$template"
  echo
  echo "# Scenario plan"
  echo
  cat "$scenario_file"
} > "$session_file"

chmod 600 "$session_file"
echo "$session_file"
