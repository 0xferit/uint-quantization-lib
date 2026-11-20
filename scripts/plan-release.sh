#!/usr/bin/env bash
set -euo pipefail

main_commit=$(git rev-parse 'refs/remotes/origin/main^{commit}')
stable_tag_pattern='^v(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$'

last_tag=$(git tag --merged "$main_commit" --sort=-version:refname |
  awk -v stable="$stable_tag_pattern" '$0 ~ stable && !tag {tag=$0} END {print tag}')

if [[ -n "${REQUESTED_TAG:-}" ]]; then
  if [[ ! "$REQUESTED_TAG" =~ $stable_tag_pattern ]]; then
    echo 'Enter a stable release tag such as v6.0.2.' >&2
    exit 1
  fi
  if ! requested_commit=$(git rev-parse --verify --quiet "refs/tags/$REQUESTED_TAG^{commit}"); then
    echo 'The requested release tag does not exist.' >&2
    exit 1
  fi
  if ! git merge-base --is-ancestor "$requested_commit" "$main_commit"; then
    echo 'The requested release tag is outside main history.' >&2
    exit 1
  fi
  printf 'pending_tag=%s\n' "$REQUESTED_TAG" >> "$GITHUB_OUTPUT"
  if [[ "$REQUESTED_TAG" != "$last_tag" ]]; then
    echo 'historical=true' >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

if [[ "$main_commit" != "$GITHUB_SHA" ]]; then
  if [[ -z "$last_tag" || "$(git rev-parse "${last_tag}^{commit}")" != "$main_commit" ||
        "$(git rev-parse "$main_commit^")" != "$GITHUB_SHA" ]]; then
    echo 'A newer main revision superseded this run.'
    exit 0
  fi
fi

solidity_diff="$RUNNER_TEMP/solidity.diff"
base=${last_tag:-$(git hash-object -t tree -w /dev/null)}
git diff "$base" "$main_commit" -- ':(glob)src/**/*.sol' > "$solidity_diff"

if [[ -n "$last_tag" ]]; then
  tag_commit=$(git rev-parse "${last_tag}^{commit}")
  marker_commit=$(git rev-parse -q --verify "$PUBLISHED_REF^{commit}" || :)
  if [[ "$tag_commit" != "$marker_commit" ]]; then
    if [[ -n "$marker_commit" ]]; then
      git merge-base --is-ancestor "$marker_commit" "$tag_commit"
    fi
    printf 'pending_tag=%s\n' "$last_tag" >> "$GITHUB_OUTPUT"
    if [[ -s "$solidity_diff" ]]; then
      echo 'follow_up=true' >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
fi

if [[ -s "$solidity_diff" ]]; then
  echo 'prepare=true' >> "$GITHUB_OUTPUT"
fi
