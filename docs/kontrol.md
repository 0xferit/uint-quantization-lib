# Kontrol Formal Verification

This project uses Kontrol as the primary verification layer on top of lightweight
Foundry regression tests.

Kontrol is used for proofs over all symbolic inputs/states for selected properties.

## Scope

Proof specs live in:

- `test/kontrol/ProofUintQuantizationSolidity.sol`

They cover:

- Core encode/decode, floor, and remainder properties.
- Lossless strict-mode properties (`isLossless`, `encodeLossless`).
- Checked-width safety (`targetBits >= 256` revert behavior).
- `maxRepresentable` overflow/boundary behavior.

## Prerequisites

Native Kontrol installed via `kup`. For Apple Silicon:

```bash
APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231
```

## Commands

```bash
# Show available proofs/specs
./script/kontrol.sh list

# Prove essential Solidity-focused specs
./script/kontrol.sh prove-core

# High-utilization profile (essential subset)
./script/kontrol.sh prove-core-hi

# Full proof set
./script/kontrol.sh prove-core-full

# Remove local proof artifacts
./script/kontrol.sh clean
```

## Profiles

- `local`: stable native defaults
- `local-hi`: tuned native profile (`workers=8`, `max-frontier-parallel=8`)
- `ci`: Docker CI defaults (`workers=8`)

## Bench and tune scripts

Benchmark and enforce CPU threshold on local runs:

```bash
./script/kontrol-bench-local.sh --command prove-core-hi --require-min-total-cpu 7
```

Tune single-process local prove flags and pick the best candidate:

```bash
./script/kontrol-tune-local.sh --min-total-cpu 7
```

## Artifacts

Kontrol artifacts are written under `.kontrol/` (gitignored).

## Counterexample workflow

If a proof fails:

1. Re-run the specific proof with `kontrol prove --match-test "<Contract.proof_name>"`.
2. Inspect generated proof artifacts under `.kontrol/`.
3. Use `kontrol show`, `kontrol list`, and `kontrol view-kcfg` for proof state/debugging.
