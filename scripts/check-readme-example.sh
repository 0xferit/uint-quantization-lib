#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
consumer=$(mktemp -d)
trap 'rm -rf "$consumer"' EXIT
mkdir -p "$consumer/src" "$consumer/dependencies/uint-quantization-lib"
cp -R src "$consumer/dependencies/uint-quantization-lib/"

awk '
  /^#+ / { section = ($0 ~ /^#+ Solidity usage$/); next }
  section && /^```solidity$/ { example = 1; next }
  example && /^```$/ { closed = 1; exit }
  example { print; if (/^contract /) contract = 1 }
  END { if (!contract || !closed) exit 1 }
' README.md > "$consumer/src/Example.sol"

printf '%s\n' '// SPDX-License-Identifier: MIT' 'pragma solidity ^0.8.25;' \
  'import "uint-quantization-lib/src/showcase/ShowcaseSolidityFixtures.sol";' > "$consumer/src/ShowcaseImport.sol"

forge build --root "$consumer" --remappings 'uint-quantization-lib/=dependencies/uint-quantization-lib/'
