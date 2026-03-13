#!/usr/bin/env bash
set -euo pipefail

# Called by @semantic-release/exec as analyzeCommitsCmd.
# Asks Claude to determine the semantic version bump from the diff.
# Falls back to "patch" if the token is missing or the call fails.

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "patch"
  exit 0
fi

# Comparison base: last successful Soldeer publish, then last release tag, then repo root.
# This ensures the bump reflects what users actually have, not intermediate failed publishes.
if git rev-parse soldeer-published >/dev/null 2>&1; then
  BASE="soldeer-published"
elif [ -n "${LAST_RELEASE_GIT_TAG:-}" ]; then
  BASE="$LAST_RELEASE_GIT_TAG"
else
  BASE=$(git rev-list --max-parents=0 HEAD)
fi

COMMIT_LOG=$(git log "$BASE"..HEAD --pretty=format:"- %s" 2>/dev/null || echo "- initial release")
DIFF_STAT=$(git diff "$BASE"..HEAD --stat 2>/dev/null | tail -30 || echo "no diff")
SOL_DIFF=$(git diff "$BASE"..HEAD -- '*.sol' 2>/dev/null | head -200 || echo "no diff")

PROMPT="You are a semantic versioning expert for a Solidity library (uint-quantization-lib).

Rules:
- major: breaking changes to the consumer-facing API (renamed functions, changed signatures, renamed/removed errors, changed type definitions)
- minor: new features (new functions, new error types, new capabilities)
- patch: bug fixes, docs, CI/CD, tests, internal refactoring, performance improvements

Respond with exactly one word: major, minor, or patch.

Commits since v${LAST_RELEASE_VERSION:-0.0.0}:
${COMMIT_LOG}

Changed files:
${DIFF_STAT}

Solidity diff (truncated):
${SOL_DIFF}"

RESPONSE=$(echo "$PROMPT" | claude --print --model opus --effort max 2>/dev/null) || { echo "patch"; exit 0; }

BUMP=$(echo "$RESPONSE" | tr '[:upper:]' '[:lower:]' | grep -oE 'major|minor|patch' | head -1)

echo "${BUMP:-patch}"
