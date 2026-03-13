# Copilot Instructions for uint-quantization-lib

## Project Overview

`uint-quantization-lib` is a pure-function Solidity library for shift-based `uint256` compression.
The core implementation is `UintQuantizationLib` in `src/UintQuantizationLib.sol`, built around
`Quant` (a `uint16` value type that packs `discardedBitWidth` and `encodedBitWidth`).

## Repository-specific guidance

- Keep library functions `internal pure` unless there is a strong reason not to.
- `Quant` layout is fixed: bits 0-7 = `discardedBitWidth`, bits 8-15 = `encodedBitWidth`.
- Keep custom errors file-level with bare names (`BadConfig`, `Overflow`, `NotAligned`).
- Keep fuzz constraints consistent with existing tests (`bound()` instead of `vm.assume`).
- For resolution-sensitive flows, prefer `encode(value, true)`; for floor truncation use `encode`.

## Validation commands

```bash
forge build
forge test
forge test --match-path test/UintQuantizationLib.t.sol
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```
