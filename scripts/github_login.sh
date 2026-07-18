#!/usr/bin/env sh
set -eu

for command_name in gh git; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

credential_dir=${SWAR_CREDENTIAL_DIR:-"$HOME/.swar"}
credential_file="$credential_dir/.git-credentials"

restore_terminal() {
  stty echo 2>/dev/null || true
}

trap restore_terminal EXIT INT TERM

echo "Paste the fine-grained GitHub token, then press Enter."
echo "The token will be stored in Swar's private credential file outside this repository."
printf "Token: "
stty -echo
IFS= read -r github_token
stty echo
printf "\n"

if [ -z "$github_token" ]; then
  echo "No token was provided." >&2
  exit 1
fi

github_login=$(GH_TOKEN="$github_token" gh api user --jq '.login')

mkdir -p "$credential_dir"
chmod 700 "$credential_dir"
touch "$credential_file"
chmod 600 "$credential_file"

printf "protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n\n" \
  "$github_token" |
  git credential-store --file="$credential_file" store

unset github_token
trap - EXIT INT TERM

echo "Authenticated GitHub account: $github_login"
echo "Stored credentials in: $credential_file"
