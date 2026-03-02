# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`uint-quantization-lib` is a pure-function Solidity library for shift-based `uint256` lossy compression. The core mechanism is floor quantization via right-shifting via the `QuantLib` library. A `Quant` constant bundles `(shift, targetBits)` into a single `uint16`, making the compression scheme explicit and reusable at zero call-site cost when declared `constant`.

## Commands

### Build and Test

```bash
# Build (compile)
forge build

# Run all tests
forge test

# Run a single test file
forge test --match-path test/UintQuantizationLib.t.sol

# Run a single test function
forge test --match-test test_encodeLossless_notAligned_reverts

# Run with verbose output
forge test -vv

# Run fuzz tests only
forge test --match-test testFuzz_

# Run showcase gas benchmarks with gas report
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

### Formal Verification (Kontrol)

Kontrol proofs for `QuantLib` are future work. The `ProofAssumptions.sol` base contract is kept for
when those proofs are written.

Requires Kontrol installed locally (Apple Silicon: `APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231`).

```bash
# List discovered proof specs
./script/kontrol.sh list

# Clean Kontrol artifacts
./script/kontrol.sh clean
```

## Architecture

### Source: `src/`

- `UintQuantizationLib.sol`: UDT `Quant` packing `(shift, targetBits)` into `uint16` (bits 0-7 = shift, bits 8-15 = targetBits). All functions are `internal pure`. Errors are file-level (not inside the library) and attached to the type. `using QuantLib for Quant global` at the bottom of the file propagates method-call binding to all importers automatically.

- `src/showcase/ShowcaseSolidityFixtures.sol`: Production-style showcase contracts demonstrating gas savings. `RawETHStakingShowcase` vs `QuantizedETHStakingShowcase` (real-life staking) and `RawExtremePackingShowcase` vs `QuantizedExtremePackingShowcase` (12 slots -> 1 slot). Used only for benchmarking. Both quantized contracts use `QuantLib`.

### Tests: `test/`

- `test/UintQuantizationLib.t.sol`: Foundry test file. Contains `QuantHarness` (exposes method-call syntax) and `QuantLibSmokeTest`. Smoke tests cover `create` validation and all revert paths. Fuzz tests use `uint8` for shift and targetBits and use `bound()` instead of `vm.assume` for value-in-range constraints.

- `test/showcase/ShowcaseGas.t.sol`: Benchmark assertions. Enforces quantized paths save >= 32% (real-life) and >= 80% (extreme) gas vs raw paths on zero-to-nonzero writes.

- `test/kontrol/ProofAssumptions.sol`: Abstract base with helpers: `_assumeShiftValid` (0 < shift < 256), `_assumeTargetBitsValid`, `_assumeNoDecodeOverflow`. Kept for future QuantLib Kontrol proofs.

### Scripts: `script/`

- `script/kontrol.sh`: Main Kontrol orchestrator. Supports `list`, `clean`. Writes toolchain metadata to `.kontrol/local-toolchain.txt`.
- `script/kontrol-bench-local.sh`: Benchmarks and enforces minimum CPU utilization threshold.
- `script/kontrol-tune-local.sh`: Tunes single-process prove flags.

### Configuration

- `foundry.toml`: `optimizer_runs = 0x10000`, fuzz `runs = 0x10000`, `libs = ["dependencies"]` (Soldeer).
- `kontrol.toml`: Profiles `default`, `ci` (workers=8, no booster), `local` (workers=8, no booster), `local-hi` (workers=8, max-frontier-parallel=8). All use `max-depth = 25000`, `smt-timeout = 1000`, `no-stack-checks = true`.
- `remappings.txt`: Maps `forge-std/` from `dependencies/`.
