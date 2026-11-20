#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export GIT_AUTHOR_NAME='Release Test' GIT_AUTHOR_EMAIL='release@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export RUNNER_TEMP="$fixture" GITHUB_OUTPUT="$fixture/plan"
export PUBLISHED_REF=refs/tags/registry-marker

git init -q "$fixture/repo"
cd "$fixture/repo"
mkdir src
main_ref=refs/remotes/origin/main

make_commit() {
  local content=$1
  shift
  printf '%s\n' "$content" > src/Example.sol
  git add -- src/Example.sol
  git commit-tree "$(git write-tree)" "$@" -m 'test: release fixture'
}

expect_plan() {
  local expected=$1
  : > "$GITHUB_OUTPUT"
  GITHUB_SHA=$2 REQUESTED_TAG=${3:-} bash "$project/scripts/plan-release.sh" >/dev/null
  local actual
  actual=$(cat "$GITHUB_OUTPUT")
  if [[ "$expected" != "$actual" ]]; then
    printf 'Expected release plan [%s], got [%s]\n' "$expected" "$actual" >&2
    exit 1
  fi
}

first=$(make_commit first)
git update-ref "$main_ref" "$first"
expect_plan 'prepare=true' "$first"

git update-ref refs/tags/v1.0.0 "$first"
git update-ref "$PUBLISHED_REF" "$first"
printf 'Documentation change\n' > README.md
git add -- README.md
docs=$(make_commit first -p "$first")
git update-ref "$main_ref" "$docs"
expect_plan '' "$docs"

release=$(make_commit release -p "$docs")
git update-ref "$main_ref" "$release"
git update-ref refs/tags/v1.1.0 "$release"
expect_plan 'pending_tag=v1.1.0' "$docs"

newest=$(make_commit newest -p "$release")
git update-ref "$main_ref" "$newest"
expect_plan $'pending_tag=v1.1.0\nfollow_up=true' "$newest"
expect_plan 'pending_tag=v1.0.0' "$newest" v1.0.0
expect_plan '' "$first"

git update-ref "$PUBLISHED_REF" "$release"
expect_plan 'prepare=true' "$newest"

echo 'Release planning checks passed.'
