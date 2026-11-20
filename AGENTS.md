# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`uint-quantization-lib` is a pure-function Solidity library for shift-based `uint256` quantization. The core mechanism is floor quantization via right-shifting. A `Quant` value type packs `(discardedBitWidth, encodedBitWidth)` into a single `uint16`, making the quantization scheme explicit and reusable. The recommended pattern is `immutable` + `create(discardedBitWidth, encodedBitWidth)`.

## Commands

```bash
forge build                                                          # compile
forge test                                                           # all tests (includes 65536 fuzz runs)
forge test --match-path test/UintQuantizationLib.t.sol               # library tests only
forge test --match-test test_encodePrecise_notAligned_reverts        # single test
forge test --match-test testFuzz_                                    # fuzz tests only
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv  # gas benchmarks
forge fmt                                                            # format Solidity files
```

## Architecture

### Core library: `src/UintQuantizationLib.sol`

- UDT `Quant` wraps `uint16`: bits 0-7 = discardedBitWidth, bits 8-15 = encodedBitWidth.
- All library functions are `internal pure`.
- Errors (`BadConfig`, `Overflow`, `NotAligned`) are file-level, not inside the library block.
- `using UintQuantizationLib for Quant global` at file bottom propagates method-call syntax to all importers automatically (no local `using` needed).
- `VERSION` constant is bumped automatically by semantic-release; do not edit it manually.

### Showcase: `src/showcase/ShowcaseSolidityFixtures.sol`

Benchmark fixtures for staking and extreme packing. The staking lifecycle and storage comparisons are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

### Tests: `test/`

- `UintQuantizationLib.t.sol`: `QuantHarness` exposes library via method-call syntax for external calls. `UintQuantizationLibSmokeTest` has concrete regression tests and fuzz tests. Fuzz parameters use `uint8` for discardedBitWidth/encodedBitWidth; use `bound()` over `vm.assume` for value-in-range constraints.
- `showcase/ShowcaseGas.t.sol`: The staking regression threshold applies to the two-slot raw baseline. Report the equal-range exact baseline alongside it. The extreme benchmark logs first-write gas.

### Configuration

- `foundry.toml`: optimizer runs = 0x10000, fuzz runs = 0x10000, deps via Soldeer (`libs = ["dependencies"]`).
- `remappings.txt`: maps `forge-std/` from `dependencies/`.

## Conventions

- Solidity `^0.8.33`, 4-space indentation, NatSpec on public-facing behavior.
- Errors are file-level with bare names (not namespaced inside the library).
- Create schemes with `UintQuantizationLib.create(...)`; never use `Quant.wrap(...)` directly.
- Showcase pairs follow `Raw...` / `Quantized...` naming.
- Test names: `test_` prefix for concrete, `testFuzz_` for fuzz. Descriptive: `test_encode_overflow_reverts`.
- Fuzz tests: `uint8` params for scheme dimensions, `bound()` not `vm.assume` for bounding values.
- Conventional Commits: `feat:`, `fix:`, `ci:`, `docs:`, `chore:`, `refactor:`, `perf:`.
- If gas numbers change, include before/after output from the showcase gas report.

## Testing doctrine

A test is worth keeping if it protects against a plausible future regression that a reviewer could miss. Write a test when at least one is true:

1. It explores more of the input space than review will (fuzz/property tests, parameterized ranges).
2. It pins a singular boundary where arithmetic or bit logic tends to fail (0, 1, max, first invalid value).
3. It captures a non-local contract (constructor invariants, checked vs unchecked semantics, round-trip relationships).
4. It documents a user-visible revert condition with non-trivial control flow.
5. It prevents a known regression or a previously identified review finding.
6. It serves as executable documentation for a tricky public semantic (one golden test per semantic, not per function).

Do not write a test that re-implements the function under test, proves the language works as documented, or duplicates coverage from a stronger fuzz/property test. For one-liners, prefer testing through richer invariants.

## Release pipeline

The release workflow runs on pushes to main and supports a manual retry on main.
It requires the same build and tests as pull requests before publication. Supply an existing stable release tag to backfill an older Soldeer version without moving the publication marker backwards.

1. `scripts/plan-release.sh` checks for Solidity changes under `src/` since the latest release tag. It retries a pending tagged release before preparing another version.
2. For a new release, `scripts/analyze-bump.sh` asks Claude to classify the Solidity diff. A missing credential, failed call or invalid classification stops the release.
3. Semantic-release updates `VERSION`, builds and tests the versioned source, and writes the changelog, GitHub release and tag.
4. The workflow uploads the tagged Solidity sources to Soldeer and verifies the registry archive. It moves the `soldeer-published` tag only after verification.
5. After retrying a pending release, run the workflow again if main contains additional unreleased Solidity changes.
