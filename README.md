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

Library: `QuantizationLib` (`src/UintQuantizationLib.sol`). Import both the type and the library:

```solidity
import {Quant, QuantizationLib} from "uint-quantization-lib-1.0.0/src/UintQuantizationLib.sol";
```

Because the source file declares `using QuantizationLib for Quant global`, importers get method-call
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
| `QuantizationLib.create(shift, targetBits)` | Creates a `Quant` scheme. Reverts with `Quant__BadConfig` when shift >= 256, targetBits == 0, targetBits >= 256, or shift + targetBits > 256. |
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
import {Quant, QuantizationLib} from "uint-quantization-lib-1.0.0/src/UintQuantizationLib.sol";

contract FeeAccumulator {
    // Scheme: 40-bit shift, 16-bit encoded width (step = 0x10000000000, max = 0xFFFF * step)
    Quant private constant SCHEME = QuantizationLib.create(40, 16);

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

## Which encode function should I use?

> - `encode` — Floor encoding with overflow check. Reverts when the value exceeds `max(q)`.
> - `encodeLossless` — Strict mode: reverts on overflow or when any precision would be lost.

Use `encode` when the caller controls or bounds the input and floor truncation is acceptable.
Use `encodeLossless` when exactness is a protocol requirement (e.g., the transaction should revert
rather than silently truncate the value).

## Showcase and gas savings

Showcase contracts under `src/showcase/` use `QuantizationLib` and compare:

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
- `stake()` uses `encode`.
- `stakeExact()` uses `encodeLossless`.
- `unstake()` uses `decode`.
- `maxDeposit()`, `stakeRemainder()`, and `isStakeLossless()` expose
  `max`, `remainder`, and `isLossless` for frontend UX.

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

Kontrol proof specs for `QuantizationLib` are future work. `test/kontrol/ProofAssumptions.sol` provides
reusable `vm.assume` helpers for when those proofs are written.

For local Apple Silicon setup:

```bash
APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231
```

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
