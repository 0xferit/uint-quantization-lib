# uint-quantization-lib

[![Staking Gas Savings](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-savings.json)](test/showcase/ShowcaseGas.t.sol)
[![Extreme Gas Savings](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/extreme-savings.json)](test/showcase/ShowcaseGas.t.sol)

A pure-function Solidity library for shift-based `uint256` compression.

Right-shift compression is lossy in general, but it becomes lossless when inputs are aligned to
the step size `2^shift` (for example, with `shift = 40`, any value that is a multiple of
`0x10000000000` is encoded exactly).

**Why?** Compress `uint256` values into smaller uints for denser storage packing. Fewer storage
slots touched per write means less gas.

**Quick start:**

```solidity
import {Quant, QuantizationLib} from "uint-quantization-lib-1.0.0/src/UintQuantizationLib.sol";

Quant private immutable SCHEME = QuantizationLib.create(32, 24);

uint24 stored = uint24(SCHEME.encode(largeValue)); // compress
uint256 restored = SCHEME.decode(stored); // decompress
```

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
| `QuantizationLib.create(shift, targetBits)` | Creates a `Quant` scheme from readable parameters. Reverts with `Quant__BadConfig` when shift >= 256, targetBits == 0, targetBits >= 256, or shift + targetBits > 256. |
| `q.shift()` | Returns the shift component (bits discarded during encoding). |
| `q.targetBits()` | Returns the targetBits component (bit-width of the encoded value). |
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
    // Recommended: immutable via create() for readability and self-documenting configs.
    Quant private immutable SCHEME = QuantizationLib.create(40, 16);

    // Optional: literal wrap when you explicitly want that style.
    // Quant layout: bits 0-7 = shift, bits 8-15 = targetBits.
    // shift=40 (0x28), targetBits=16 (0x10) → Quant.wrap(0x1028)
    // Quant private constant SCHEME = Quant.wrap(0x1028);

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

> `encode()` and `encodeLossless()` return `uint256` due to Solidity type constraints. The encoded
> result is guaranteed to fit in `2^targetBits - 1`, so store it using the matching `uintN` for
> your scheme (for example, `uint16` for `targetBits=16`, `uint24` for `targetBits=24`). Using a
> smaller type will silently truncate.

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
| Solidity real-life staking | 65,921 | 44,045 | 33.19% |
| Solidity extreme (12 slots -> 1 slot) | 290,061 | 52,147 | 82.02% |

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
