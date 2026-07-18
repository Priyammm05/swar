#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$project_root/quality/user-testing/scenarios/manifest.txt"

if [ ! -f "$manifest" ]; then
  echo "User-testing manifest is missing." >&2
  exit 1
fi

plan_count=0
while IFS='|' read -r plan_name scenario_path; do
  case "$plan_name" in
    ''|'#'*) continue ;;
  esac

  plan_count=$((plan_count + 1))
  scenario_file="$project_root/$scenario_path"

  if [ ! -f "$scenario_file" ]; then
    echo "Missing scenario for $plan_name: $scenario_path" >&2
    exit 1
  fi

  if ! grep -Eq '^## Task [A-Z0-9-]+:' "$scenario_file"; then
    echo "Scenario has no stable task ID: $scenario_path" >&2
    exit 1
  fi

  for required_heading in '### Success criteria' '### Observe' '## Session completion'; do
    if ! grep -Fq "$required_heading" "$scenario_file"; then
      echo "Scenario is missing '$required_heading': $scenario_path" >&2
      exit 1
    fi
  done
done < "$manifest"

if [ "$plan_count" -eq 0 ]; then
  echo "User-testing manifest contains no plans." >&2
  exit 1
fi

echo "Verified $plan_count individual-user test plan(s)."
