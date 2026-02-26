# uint-quantization-lib

A pure-function Solidity/Vyper library for shift-based `uint256` compression.

Right-shift compression is lossy in general, but it becomes lossless when inputs are aligned to
the step size `2^shift` (for example, with `shift = 40`, any value that is a multiple of
`0x10000000000` is encoded exactly).

## Installation

```bash
forge soldeer install uint-quantization-lib~1.0.0
```

Then add the remapping to `foundry.toml` (Soldeer does this automatically):

```toml
[profile.default]
remappings = ["uint-quantization-lib-1.0.0/=dependencies/uint-quantization-lib-1.0.0/"]
```

## Solidity API

Library: `UintQuantizationLib` (`src/UintQuantizationLib.sol`).

### Encode / decode

| Function | Description |
|---|---|
| `encode(uint256 value, uint256 shift)` | Floor encoding (`value >> shift`). |
| `encodeCeil(uint256 value, uint256 shift)` | Ceiling encoding (rounds up if discarded bits are non-zero). |
| `decode(uint256 compressed, uint256 shift)` | Lower-bound decode (`compressed << shift`). |
| `decodeCeil(uint256 compressed, uint256 shift)` | Upper-bound decode (`(compressed << shift) \| ((1 << shift) - 1)`). |

### Lossless mode

| Function | Description |
|---|---|
| `isLossless(uint256 value, uint256 shift)` | Returns `true` when `value` is exactly representable at `shift` (`value % 2^shift == 0`). |
| `encodeLossless(uint256 value, uint256 shift)` | Strict mode: reverts with `UintQuantizationLib__InexactInput` if not step-aligned. |
| `encodeLosslessChecked(uint256 value, uint256 shift, uint256 targetBits)` | Strict + width-checked mode. |

### Width-safe helpers

| Function | Description |
|---|---|
| `encodeChecked(uint256 value, uint256 shift, uint256 targetBits)` | Reverts if encoded value does not fit `targetBits`. |
| `encodeCeilChecked(uint256 value, uint256 shift, uint256 targetBits)` | Same as above for ceiling mode. |
| `maxRepresentable(uint256 shift, uint256 targetBits)` | Max value that fits after encoding to `targetBits`. |

### Introspection

| Function | Description |
|---|---|
| `stepSize(uint256 shift)` | Returns `2^shift`. |
| `remainder(uint256 value, uint256 shift)` | Returns discarded low bits. |

### Errors

```solidity
error UintQuantizationLib__Overflow(uint256 encoded, uint256 targetBits);
error UintQuantizationLib__InvalidShift(uint256 shift);
error UintQuantizationLib__InexactInput(uint256 value, uint256 shift, uint256 remainder);
```

## Lossless signaling pattern

Client-side flow for strict precision:

1. Choose a protocol constant `SHIFT`.
2. Validate `isLossless(value, SHIFT)` before sending the transaction.
3. On-chain, call `encodeLosslessChecked(value, SHIFT, targetBits)` to enforce both exactness and
   width safety.

## Solidity usage

```solidity
import {UintQuantizationLib} from "uint-quantization-lib-1.0.0/src/UintQuantizationLib.sol";

contract FeeAccumulator {
    using UintQuantizationLib for uint256;

    uint256 private constant SHIFT = 40; // step size = 0x10000000000
    uint56 public storedFee;

    function setFeeStrict(uint256 fee) external {
        storedFee = uint56(fee.encodeLosslessChecked(SHIFT, 56));
    }

    function setFeeBounded(uint256 fee) external {
        storedFee = uint56(fee.encodeCeilChecked(SHIFT, 56));
    }

    function getFeeLower() external view returns (uint256) {
        return uint256(storedFee).decode(SHIFT);
    }

    function getFeeUpper() external view returns (uint256) {
        return uint256(storedFee).decodeCeil(SHIFT);
    }
}
```

## Showcase and gas savings

Showcase contracts under `src/showcase/` compare:

- Real-life example (production-style ETH staking):
  raw path uses realistic packed fields by default (`uint128 amount`, `uint64` timestamps, `bool active`)
  in `RawETHStakingShowcase`, while the quantized path further compresses stake amount into `uint96`
  in `QuantizedETHStakingShowcase`.
- Extreme example (upper-bound packing showcase):
  raw path stores 12 full-width `uint256` values (`RawExtremePackingShowcase`),
  quantized path packs all 12 into 1 slot (`QuantizedExtremePackingShowcase`).

This demonstrates where quantization creates real gas savings: fewer storage writes and denser
state layout.

The staking showcase intentionally exercises the full API surface:
- `stake()` uses `encodeChecked`.
- `stakeExact()` uses `encodeLosslessChecked`.
- `unstake()` uses `decode`.
- `quoteProtocolFee()` uses `encodeCeil`.
- `maxDeposit()`, `stakeRemainder()`, and `isStakeLossless()` expose
  `maxRepresentable`, `remainder`, and `isLossless` for frontend UX.

Benchmark assertions live in `test/showcase/ShowcaseGas.t.sol`.

Run the showcase suite:

```bash
forge test --match-path test/showcase/ShowcaseGas.t.sol -vv
```

Run with gas report:

```bash
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

The suite enforces that quantized write paths save at least:
- 32% for the real-life showcase.
- 80% for the extreme showcase.
These threshold checks run for both Solidity and Vyper zero-to-nonzero writes.

The suite also records nonzero-to-nonzero (warm overwrite) metrics without hard thresholds:
- `test_gas_real_life_*_nonzero_to_nonzero_metrics`
- `test_gas_extreme_*_nonzero_to_nonzero_metrics`

Current benchmark snapshot (`forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv`):

| Scenario | Raw write gas | Quantized floor write gas | Savings |
|---|---:|---:|---:|
| Solidity real-life staking | 65,921 | 43,920 | 33.37% |
| Vyper real-life staking | 65,670 | 43,733 | 33.41% |
| Solidity extreme (12 slots -> 1 slot) | 290,061 | 49,231 | 83.03% |
| Vyper extreme (12 slots -> 1 slot) | 289,836 | 48,676 | 83.21% |

Warm overwrite snapshot (`forge test --match-path test/showcase/ShowcaseGas.t.sol -vv`):

| Scenario | Raw warm write gas | Quantized floor warm write gas | Quantized strict warm write gas |
|---|---:|---:|---:|
| Solidity real-life staking | 1,057 | 956 | 1,184 |
| Vyper real-life staking | 606 | 669 | 843 |
| Solidity extreme (12 lanes) | 2,885 | 4,055 | 7,142 |
| Vyper extreme (12 lanes) | 2,660 | 3,500 | 6,234 |

On warm overwrites, quantized paths are not guaranteed to be cheaper. Once cold-slot costs are gone,
fixed encode/packing overhead can narrow or invert the gas advantage depending on the path.

## Vyper

Module: `src/UintQuantizationLib.vy`.

### Prerequisites

```bash
python3 --version   # requires Python >= 3.10 for Vyper 0.4.x
pip install "vyper>=0.4.0,<0.5"
vyper --version     # confirm 0.4.x
```

### Import

```vyper
from uint-quantization-lib-1.0.0.src import UintQuantizationLib as lib

SHIFT: constant(uint256) = 40

stored: uint56 = uint56(lib.encode_lossless_checked(value, SHIFT, 56))
restored: uint256 = lib.decode(convert(stored, uint256), SHIFT)
```

Vyper names are snake_case equivalents:
`encode_ceil`, `decode_ceil`, `step_size`, `max_representable`, `is_lossless`,
`encode_lossless`, `encode_lossless_checked`.

## Formal verification (Kontrol)

Kontrol proof specs are under `test/kontrol/`.

For local Apple Silicon runs, use native Kontrol (no Docker), starting with the
`kup`-installed `aarch64-darwin` release:

```bash
# one-time local install
APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231
pip install "vyper==0.4.3"

# local proving
./script/kontrol.sh list
./script/kontrol.sh prove-core
./script/kontrol.sh prove-parity

# high-utilization profile commands (essential subset)
./script/kontrol.sh prove-core-hi
./script/kontrol.sh prove-parity-hi

# full suites (re-enable broader coverage later)
./script/kontrol.sh prove-core-full
./script/kontrol.sh prove-parity-full
```

Each local run writes `.kontrol/local-toolchain.txt` with the detected local
binary path and tool versions.

Profiles:
- `local`: stable native defaults
- `local-hi`: tuned native profile (`workers=8`, `max-frontier-parallel=8`)
- `ci`: Docker CI defaults (`workers=8`)

```bash
kontrol prove --config-file kontrol.toml --config-profile local --reinit --match-test "ProofUintQuantizationSolidity.prove_.*target_bits_256_reverts.*"
kontrol prove --config-file kontrol.toml --config-profile local --reinit --match-test "ProofUintQuantizationVyper.prove_parity_encode_checked.*"
```

Benchmark and enforce CPU threshold on local runs:

```bash
./script/kontrol-bench-local.sh --command prove-core-hi --require-min-total-cpu 7
```

Tune single-process local prove flags and pick the best candidate:

```bash
./script/kontrol-tune-local.sh --min-total-cpu 7
```

If no `kup` release candidate meets the required local CPU threshold, escalate to
a source-build toolchain track and repeat benchmarking/tuning.

When the core workflow is stable again, expand to `prove-core-full` and
`prove-parity-full`.

The default essential profile is intentionally minimal for fast local/CI iteration:
target-bit guard proofs and one Solidity/Vyper parity check. Use `prove-core-full` and
`prove-parity-full` to restore the full semantic property set.
On high-core machines, this essential profile typically saturates only a few cores, so
total CPU percentages in the ~7-25% range are expected.

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
