#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
classifier=node_modules/@anthropic-ai/claude-code-linux-x64/claude
mkdir -p "$(dirname "$classifier")"
cat > "$classifier" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$REPLY_TEXT"
exit "${REPLY_STATUS:-0}"
STUB
chmod +x "$classifier"
printf '%s\n' '+function withdraw() external;' > solidity.diff
export CLAUDE_CODE_OAUTH_TOKEN=fixture

expect_bump() {
  local actual
  actual=$(REPLY_TEXT="$1" bash "$project/scripts/analyze-bump.sh" solidity.diff)
  if [[ "$actual" != "$2" ]]; then
    printf 'Expected [%s] for [%s], got [%s]\n' "$2" "$1" "$actual" >&2
    exit 1
  fi
}

expect_rejection() {
  if REPLY_TEXT="$1" bash "$project/scripts/analyze-bump.sh" solidity.diff > output 2> diagnostic; then
    printf 'Unexpectedly accepted [%s]\n' "$1" >&2
    exit 1
  fi
  [[ ! -s output ]]
}

expect_bump 'Patch' patch
expect_bump 'patch.' patch
expect_bump '**minor**' minor
expect_bump $'\n\t`MAJOR`. \r\n' major
expect_bump 'minor' minor
for reply in '' '**minor*' 'minors' 'patch or minor' $'patch\nmajor' 'not a patch'; do
  expect_rejection "$reply"
done
reply=$'Possibly **Major**.\n\n  Or Patch?  \n\n'
GITHUB_ACTIONS=true expect_rejection "$reply"
log_token=$(sed -n 's/^::stop-commands:://p' diagnostic)
[[ -n $log_token ]]
printf '%s\n' "::stop-commands::$log_token" "$reply" '' "::$log_token::" > expected-reply
tail -c "$(wc -c < expected-reply)" diagnostic | cmp expected-reply -

REPLY_STATUS=1 expect_rejection 'major'
CLAUDE_CODE_OAUTH_TOKEN='' expect_rejection 'patch'
echo 'Release classifier checks passed.'
