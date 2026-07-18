#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 OWNER/REPOSITORY [COMMIT_MESSAGE]" >&2
  exit 1
fi

repository=$1
commit_message=${2:-"Publish Swar workspace"}
branch=${SWAR_GITHUB_BRANCH:-main}
workspace_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
credential_file=${SWAR_GITHUB_CREDENTIAL_FILE:-"$HOME/.swar/.git-credentials"}

for command_name in gh git jq base64; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

case "$repository" in
  */*) ;;
  *)
    echo "Repository must use the OWNER/REPOSITORY format." >&2
    exit 1
    ;;
esac

if [ ! -f "$credential_file" ]; then
  echo "Swar GitHub credentials are missing. Run ./scripts/github_login.sh first." >&2
  exit 1
fi

credential_output=$(printf "protocol=https\nhost=github.com\n\n" |
  git credential-store --file="$credential_file" get)
github_token=$(printf "%s\n" "$credential_output" | sed -n 's/^password=//p')
unset credential_output

if [ -z "$github_token" ]; then
  echo "No GitHub token was found in Swar's credential store." >&2
  exit 1
fi

export GH_TOKEN="$github_token"
unset github_token

gh auth status --hostname github.com >/dev/null
gh api "repos/$repository" >/dev/null

publish_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/swar-github-publish.XXXXXX")
cleanup() {
  rm -rf "$publish_temp_dir"
}
trap cleanup EXIT INT TERM

git init --quiet "$publish_temp_dir/git"

head_sha=""
if head_sha=$(gh api "repos/$repository/git/ref/heads/$branch" --jq '.object.sha' 2>/dev/null); then
  :
else
  head_sha=""
fi

if [ -z "$head_sha" ]; then
  initial_content=$(base64 <"$workspace_dir/.gitignore" | tr -d '\n')
  gh api --method PUT "repos/$repository/contents/.gitignore" \
    -f message="Initialize Swar repository" \
    -f content="$initial_content" >/dev/null
  unset initial_content
  head_sha=$(gh api "repos/$repository/git/ref/heads/$branch" --jq '.object.sha')
fi

base_tree_sha=$(gh api "repos/$repository/git/commits/$head_sha" --jq '.tree.sha')

jq -n --arg base_tree "$base_tree_sha" \
  '{base_tree: $base_tree, tree: []}' >"$publish_temp_dir/tree.json"

if [ -n "${SWAR_PUBLISH_PATHS_FILE:-}" ]; then
  if [ ! -f "$SWAR_PUBLISH_PATHS_FILE" ]; then
    echo "Publish path manifest does not exist: $SWAR_PUBLISH_PATHS_FILE" >&2
    exit 1
  fi
  cp "$SWAR_PUBLISH_PATHS_FILE" "$publish_temp_dir/paths.txt"
else
  git --git-dir="$publish_temp_dir/git/.git" \
    --work-tree="$workspace_dir" \
    ls-files --others --exclude-standard >"$publish_temp_dir/paths.txt"
fi

while IFS= read -r relative_path; do
  case "$relative_path" in
    ""|'#'*) continue ;;
    /*|../*|*/../*)
      echo "Unsafe publish path: $relative_path" >&2
      exit 1
      ;;
  esac

  if git --git-dir="$publish_temp_dir/git/.git" \
    --work-tree="$workspace_dir" check-ignore --quiet "$relative_path"; then
    echo "Refusing to publish ignored path: $relative_path" >&2
    exit 1
  fi

  printf '%s\n' "$relative_path"
done <"$publish_temp_dir/paths.txt" |
while IFS= read -r relative_path; do
  file_path="$workspace_dir/$relative_path"

  if [ ! -f "$file_path" ]; then
    continue
  fi

  base64 <"$file_path" | tr -d '\n' >"$publish_temp_dir/blob.base64"
  jq -n \
    --rawfile content "$publish_temp_dir/blob.base64" \
    '{content: $content, encoding: "base64"}' \
    >"$publish_temp_dir/blob.json"
  blob_sha=$(gh api --method POST "repos/$repository/git/blobs" \
    --input "$publish_temp_dir/blob.json" \
    --jq '.sha')

  file_mode=100644
  if [ -x "$file_path" ]; then
    file_mode=100755
  fi

  jq \
    --arg path "$relative_path" \
    --arg mode "$file_mode" \
    --arg sha "$blob_sha" \
    '.tree += [{path: $path, mode: $mode, type: "blob", sha: $sha}]' \
    "$publish_temp_dir/tree.json" >"$publish_temp_dir/tree.next.json"
  mv "$publish_temp_dir/tree.next.json" "$publish_temp_dir/tree.json"
done

tree_sha=$(gh api --method POST "repos/$repository/git/trees" \
  --input "$publish_temp_dir/tree.json" \
  --jq '.sha')

jq -n \
  --arg message "$commit_message" \
  --arg tree "$tree_sha" \
  --arg parent "$head_sha" \
  '{message: $message, tree: $tree, parents: [$parent]}' \
  >"$publish_temp_dir/commit.json"

commit_sha=$(gh api --method POST "repos/$repository/git/commits" \
  --input "$publish_temp_dir/commit.json" \
  --jq '.sha')

gh api --method PATCH "repos/$repository/git/refs/heads/$branch" \
  -f sha="$commit_sha" \
  -F force=false >/dev/null

echo "Published commit $commit_sha to $repository on branch $branch."
