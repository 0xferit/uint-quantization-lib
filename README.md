# uint-quantization-lib

A pure-function Solidity library for shift-based `uint256` compression.

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
| `decode(uint256 compressed, uint256 shift)` | Decode (`compressed << shift`). |

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

## Worked example

With `SHIFT = 4` and `WIDTH = 8`:

| Parameter | Calculation | Result |
|---|---|---|
| Step size | `2^4` | `16` |
| Max encodable value | `(2^8 - 1) << 4` = `255 * 16` | `4080` |

Concrete encode → decode round-trip showing floor behavior:

```solidity
encode(100, 4)     // 100 >> 4 = 6
decode(6, 4)       // 6 << 4 = 96
remainder(100, 4)  // 100 % 16 = 4
```

In this example:
- The original value `100` is floored to `96` after the round-trip.
- The discarded precision is `4` (the remainder).
- All values in the range `96` to `111` encode to the same compressed value `6`.

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
        storedFee = uint56(fee.encodeChecked(SHIFT, 56));
    }

    function getFee() external view returns (uint256) {
        return uint256(storedFee).decode(SHIFT);
    }
}
```

## QuantLib

`QuantLib` (`src/UintQuantLib.sol`) bundles `(shift, targetBits)` into a single `Quant` constant,
enabling zero-cost call-site unpacking when the scheme is declared `constant`. Import both the type
and the library:

```solidity
import {Quant, QuantLib} from "uint-quantization-lib-1.0.0/src/UintQuantLib.sol";
```

Because the source file declares `using QuantLib for Quant global`, importers get method-call
syntax automatically without a local `using` statement.

### Type layout

The `Quant` value type is a `uint16` with the following bit layout:

| Bits | Field | Notes |
|---|---|---|
| 0-7 | `shift` | LSBs discarded during encoding |
| 8-15 | `targetBits` | Bit-width of the encoded value |

### API

| Function | Description |
|---|---|
| `QuantLib.create(shift, targetBits)` | Creates a `Quant` scheme. Reverts with `Quant__BadConfig` when shift >= 256, targetBits == 0, targetBits >= 256, or shift + targetBits > 256. |
| `q.encode(value)` | Floor-encodes `value`. Reverts with `Quant__Overflow` when `value > max(q)`. |
| `q.encodeLossless(value)` | Strict mode: also reverts with `Quant__NotAligned` when `value` is not step-aligned. |
| `q.decode(encoded)` | Left-shifts `encoded` by shift, restoring discarded bits as zeros (lower bound). |
| `q.decodeMax(encoded)` | Like `decode` but fills discarded bits with ones (upper bound within the step). |
| `q.fits(value)` | Returns `true` when `value <= max(q)`. |
| `q.floor(value)` | Rounds `value` down to the nearest step boundary. |
| `q.ceil(value)` | Rounds `value` up to the nearest step boundary. |
| `q.remainder(value)` | Returns discarded low bits (`value mod stepSize`). |
| `q.isLossless(value)` | Returns `true` when `value` is exactly representable (step-aligned). |
| `q.stepSize()` | Returns `2^shift`. |
| `q.max()` | Returns the maximum original value representable: `(2^targetBits - 1) << shift`. |

### Errors

```solidity
error Quant__BadConfig(uint256 shift, uint256 targetBits);
error Quant__Overflow(uint256 value, uint256 max);
error Quant__NotAligned(uint256 value, uint256 stepSize);
```

### Solidity usage

```solidity
import {Quant, QuantLib} from "uint-quantization-lib-1.0.0/src/UintQuantLib.sol";

contract FeeAccumulator {
    // Scheme: 40-bit shift, 16-bit encoded width (step = 0x10000000000, max = 0xFFFF * step)
    Quant private constant SCHEME = QuantLib.create(40, 16);

    uint16 public storedFee;

    function setFeeExact(uint256 fee) external {
        storedFee = uint16(SCHEME.encodeLossless(fee));
    }

    function setFeeBounded(uint256 fee) external {
        storedFee = uint16(SCHEME.encode(fee));
    }

    function getFee() external view returns (uint256) {
        return SCHEME.decode(storedFee);
    }

    function maxDeposit() external view returns (uint256) {
        return SCHEME.max();
    }
}
```

### Which library should I use?

| Use `UintQuantizationLib` when... | Use `QuantLib` when... |
|---|---|
| You call encode/decode at isolated sites with different shift values each time. | You define a compression scheme once as a contract constant and reuse it across multiple call sites. |
| You want direct `uint256.encode(shift)` method syntax via `using`. | You want `scheme.encode(value)` method syntax on the scheme itself. |
| You need `maxRepresentable(shift, targetBits)` as a standalone helper. | You want the scheme to carry its own `max()`, `stepSize()`, and width semantics. |
| Formal verification (Kontrol proofs exist for this library). | You prefer a single import with no local `using` statement needed. |

> Note: `Quant__Overflow` reports `(value, max)` while `UintQuantizationLib__Overflow` reports
> `(encoded, targetBits)` — the parameter semantics differ intentionally because the two libraries
> operate at different abstraction levels.

## Which encode function should I use?

> - `encode` — Fast, unchecked floor encoding. Use when you know the value fits.
> - `encodeChecked` — Reverts on overflow (value does not fit `targetBits`). Use for safe storage writes.
> - `encodeLossless` — Reverts if any precision is lost. Use when exactness matters.
> - `encodeLosslessChecked` — Reverts on overflow OR precision loss. Strictest mode.

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
These threshold checks run for Solidity zero-to-nonzero writes.

Current benchmark snapshot (`forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv`):

| Scenario | Raw write gas | Quantized floor write gas | Savings |
|---|---:|---:|---:|
| Solidity real-life staking | 65,921 | 43,920 | 33.37% |
| Solidity extreme (12 slots -> 1 slot) | 290,061 | 49,231 | 83.03% |

## Formal verification (Kontrol)

Kontrol proof specs are under `test/kontrol/`.

For local Apple Silicon runs, use native Kontrol (no Docker), starting with the
`kup`-installed `aarch64-darwin` release:

```bash
# one-time local install
APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231

# local proving
./script/kontrol.sh list
./script/kontrol.sh prove-core

# high-utilization profile command (essential subset)
./script/kontrol.sh prove-core-hi

# full suite (re-enable broader coverage later)
./script/kontrol.sh prove-core-full
```

Each local run writes `.kontrol/local-toolchain.txt` with the detected local
binary path and tool versions.

Profiles:
- `local`: stable native defaults
- `local-hi`: tuned native profile (`workers=8`, `max-frontier-parallel=8`)
- `ci`: Docker CI defaults (`workers=8`)

```bash
kontrol prove --config-file kontrol.toml --config-profile local --reinit --match-test "ProofUintQuantizationSolidity.prove_.*target_bits_256_reverts.*"
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

When the core workflow is stable again, expand to `prove-core-full`.

The default essential profile is intentionally minimal for fast local/CI iteration:
target-bit guard proofs. Use `prove-core-full` to restore the full semantic property set.
On high-core machines, this essential profile typically saturates only a few cores, so
total CPU percentages in the ~7-25% range are expected.

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
