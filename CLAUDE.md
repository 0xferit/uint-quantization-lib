# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`uint-quantization-lib` is a pure-function Solidity library for shift-based `uint256` lossy compression. The core mechanism is floor quantization via right-shifting: `encode(value, shift) = value >> shift`, `decode(compressed, shift) = compressed << shift`. Encoding is lossless when inputs are aligned to `2^shift`.

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
forge test --match-test test_encodeLossless_inexact_reverts

# Run with verbose output
forge test -vv

# Run fuzz tests only
forge test --match-test testFuzz_

# Run showcase gas benchmarks with gas report
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

### Formal Verification (Kontrol)

Requires Kontrol installed locally (Apple Silicon: `APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231`).

```bash
# List discovered proof specs
./script/kontrol.sh list

# Prove essential subset (target-bits guard proofs): fastest iteration
./script/kontrol.sh prove-core

# Prove with high-utilization profile (workers=8)
./script/kontrol.sh prove-core-hi

# Prove full spec set
./script/kontrol.sh prove-core-full

# Clean Kontrol artifacts
./script/kontrol.sh clean

# Prove a single spec directly
kontrol prove --config-file kontrol.toml --config-profile local --reinit \
  --match-test "ProofUintQuantizationSolidity.prove_<name>"
```

## Architecture

### Source: `src/`

- `UintQuantizationLib.sol`: The entire library in one file. All functions are `internal pure`. Three error types cover overflow, invalid shift, and inexact input. Key design: `encode`/`decode` are unchecked (EVM handles shift >= 256 gracefully); strict variants (`encodeLossless`, `encodeLosslessChecked`) call `_requireValidShift` to prevent silent data loss.

- `UintQuantLib.sol`: UDT `Quant` packing `(shift, targetBits)` into `uint16` (bits 0-7 = shift, bits 8-15 = targetBits). All functions are `internal pure`. Errors are file-level (not inside the library) and attached to the type. `using QuantLib for Quant global` at the bottom of the file propagates method-call binding to all importers automatically.

- `src/showcase/ShowcaseSolidityFixtures.sol`: Production-style showcase contracts demonstrating gas savings. `RawETHStakingShowcase` vs `QuantizedETHStakingShowcase` (real-life staking) and `RawExtremePackingShowcase` vs `QuantizedExtremePackingShowcase` (12 slots -> 1 slot). Used only for benchmarking.

### Tests: `test/`

- `test/UintQuantizationLib.t.sol`: Foundry test file. Contains `UintQuantizationHarness` (exposes `using-for` syntax) and `UintQuantizationLibSmokeTest`. Tests are concrete regression checks; mathematical completeness is delegated to Kontrol proofs. Fuzz tests use `uint8` for shift to constrain the space.

- `test/UintQuantLib.t.sol`: Foundry test file. Contains `QuantHarness` (exposes method-call syntax) and `QuantLibSmokeTest`. Smoke tests cover `create` validation and all revert paths. Fuzz tests use `uint8` for shift and targetBits and use `bound()` instead of `vm.assume` for value-in-range constraints.

- `test/showcase/ShowcaseGas.t.sol`: Benchmark assertions. Enforces quantized paths save >= 32% (real-life) and >= 80% (extreme) gas vs raw paths on zero-to-nonzero writes.

- `test/kontrol/ProofUintQuantizationSolidity.sol`: Kontrol formal proof specs. Uses `prove_` prefix convention. Extends `ProofAssumptions` for shared `vm.assume` helpers.

- `test/kontrol/ProofAssumptions.sol`: Abstract base with helpers: `_assumeShiftValid` (0 < shift < 256), `_assumeTargetBitsValid`, `_assumeNoDecodeOverflow`.

### Scripts: `script/`

- `script/kontrol.sh`: Main Kontrol orchestrator. Supports `prove-core`, `prove-core-hi`, `prove-core-full`, `list`, `clean`. Writes toolchain metadata to `.kontrol/local-toolchain.txt`.
- `script/kontrol-bench-local.sh`: Benchmarks and enforces minimum CPU utilization threshold.
- `script/kontrol-tune-local.sh`: Tunes single-process prove flags.

### Configuration

- `foundry.toml`: `optimizer_runs = 0x10000`, fuzz `runs = 0x10000`, `libs = ["dependencies"]` (Soldeer).
- `kontrol.toml`: Profiles `default`, `ci` (workers=8, no booster), `local` (workers=8, no booster), `local-hi` (workers=8, max-frontier-parallel=8). All use `max-depth = 25000`, `smt-timeout = 1000`, `no-stack-checks = true`.
- `remappings.txt`: Maps `forge-std/` from `dependencies/`.

## Key Invariants

The library's mathematical properties verified by Kontrol:

1. `decode(encode(v, s), s) <= v` (floor lower bound)
2. `remainder(v, s) < stepSize(s)` (remainder is bounded)
3. `remainder(v, s) == v - decode(encode(v, s), s)` (remainder identity)
4. `isLossless(v, s) <=> remainder(v, s) == 0`
5. `isLossless(v, s) => decode(encodeLossless(v, s), s) == v` (exact round-trip)
6. `encodeChecked`, `encodeLosslessChecked`, `maxRepresentable` revert when `targetBits >= 256`
