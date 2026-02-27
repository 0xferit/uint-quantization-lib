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

Docker daemon running locally (`docker info`).

## Commands

```bash
# Show available proofs/specs
./script/kontrol.sh list

# Prove Solidity-focused specs
./script/kontrol.sh prove-core

# Remove local proof artifacts
./script/kontrol.sh clean
```

Alternative Docker image (override):

```bash
KONTROL_DOCKER_IMAGE=runtimeverificationinc/kontrol:ubuntu-jammy-1.0.231 \
  ./script/kontrol.sh prove-core
```

## Artifacts

Kontrol artifacts are written under `.kontrol/` (gitignored).

## Counterexample workflow

If a proof fails:

1. Re-run the specific proof with `kontrol prove --match-test "<Contract.proof_name>"`.
2. Inspect generated proof artifacts under `.kontrol/`.
3. Use `kontrol show`, `kontrol list`, and `kontrol view-kcfg` for proof state/debugging.
