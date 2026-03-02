# Kontrol Formal Verification

This project uses Kontrol as the primary verification layer on top of lightweight
Foundry regression tests.

Kontrol is used for proofs over all symbolic inputs/states for selected properties.

## Scope

Kontrol proofs for the `QuantLib` UDT API are planned but not yet written.
The proof infrastructure (scripts, config, docs) is maintained so proofs
can be added incrementally.

### Planned proof coverage

- `create` validation: rejects all four invalid parameter combinations
- encode/decode round-trip: `decode(q, encode(q, v)) <= v` for all valid v
- `encodeLossless` exact round-trip: `decode(q, encodeLossless(q, v)) == v`
- `encodeLossless` revert on misalignment
- `remainder` < `stepSize` for all inputs
- `isLossless` iff `remainder == 0`
- `ceil(q, v) >= v` (with overflow guard)
- `floor` produces lossless values
- `encode` monotonicity: `v1 <= v2` implies `encode(q, v1) <= encode(q, v2)`
- `decodeMax(q, e) >= decode(q, e)` for all e
- `fits(q, v)` iff `v <= max(q)`

## Prerequisites

Native Kontrol installed via `kup`. For Apple Silicon:

```bash
APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231
```

## Commands

```bash
# Show available proofs/specs
./script/kontrol.sh list

# Remove local proof artifacts
./script/kontrol.sh clean
```

## Artifacts

Kontrol artifacts are written under `.kontrol/` (gitignored).

## Counterexample workflow

If a proof fails:

1. Re-run the specific proof with `kontrol prove --match-test "<Contract.proof_name>"`.
2. Inspect generated proof artifacts under `.kontrol/`.
3. Use `kontrol show`, `kontrol list`, and `kontrol view-kcfg` for proof state/debugging.
