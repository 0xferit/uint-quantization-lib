# uint-quantization-lib

[![Staking Case: Gas Usage Reduction](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-savings.json)](test/showcase/ShowcaseGas.t.sol)
[![Extreme Case: Gas Usage Reduction](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/extreme-savings.json)](test/showcase/ShowcaseGas.t.sol)

Token amounts carry 18 decimals of precision. Timestamps fit in 40 bits but live in `uint64`. Oracle prices, counters, accumulated fees: most on-chain values use far more resolution than the application needs, and every extra storage slot costs 20,000 gas on a cold write.

This library quantizes `uint256` values via right-shift compression, packing more fields per storage slot and cutting gas on every write.

**Quick start:**

```solidity
import {Quant, QuantizationLib} from "uint-quantization-lib/src/UintQuantizationLib.sol";

Quant private immutable SCHEME = QuantizationLib.create(32, 24);

uint24 stored = uint24(SCHEME.encode(largeValue)); // compress
uint256 restored = SCHEME.decode(stored); // decompress
```

## Installation

```bash
forge soldeer install uint-quantization-lib
```

Then add the remapping to `foundry.toml` (Soldeer does this automatically):

```toml
[profile.default]
remappings = ["uint-quantization-lib/=dependencies/uint-quantization-lib/"]
```

## Solidity API

Library: `QuantizationLib` (`src/UintQuantizationLib.sol`). Import both the `Quant` type and the
library as shown in the [usage example](#solidity-usage) below.

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
| `QuantizationLib.create(shift, targetBits)` | Creates a `Quant` scheme from readable parameters. Reverts with `BadConfig` when shift >= 256, targetBits == 0, targetBits >= 256, or shift + targetBits > 256. |
| `q.shift()` | Returns the shift component (bits discarded during encoding). |
| `q.targetBits()` | Returns the targetBits component (bit-width of the encoded value). |
| `q.encode(value)` | Floor-encodes `value`. Reverts with `Overflow` when `value > max(q)`. |
| `q.encodeLossless(value)` | Strict mode: also reverts with `NotAligned` when `value` is not step-aligned. |
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
error BadConfig(uint256 shift, uint256 targetBits);
error Overflow(uint256 value, uint256 max);
error NotAligned(uint256 value, uint256 stepSize);
```

### Solidity usage

```solidity
import {Quant, QuantizationLib} from "uint-quantization-lib/src/UintQuantizationLib.sol";

contract StakingVault {
    Quant private immutable SCHEME = QuantizationLib.create(16, 96);

    mapping(address => uint96) internal stakes;

    /// Floor-encodes msg.value and stores the compressed amount.
    function stake() external payable {
        require(SCHEME.fits(msg.value), "amount exceeds scheme max");
        stakes[msg.sender] = uint96(SCHEME.encode(msg.value));
    }

    /// Strict mode: reverts if msg.value is not step-aligned.
    function stakeExact() external payable {
        stakes[msg.sender] = uint96(SCHEME.encodeLossless(msg.value));
    }

    /// Restores the lower-bound value (what was actually stored).
    function stakeOf(address user) external view returns (uint256) {
        return SCHEME.decode(stakes[user]);
    }

    /// Upper-bound value: original was at most this much.
    function stakeMaxOf(address user) external view returns (uint256) {
        return SCHEME.decodeMax(stakes[user]);
    }

    /// Largest value the scheme can represent.
    function maxDeposit() external pure returns (uint256) {
        return SCHEME.max();
    }

    /// Minimum granularity: values must be multiples of this for lossless encoding.
    function depositGranularity() external pure returns (uint256) {
        return SCHEME.stepSize();
    }

    /// Bits that would be lost if `amount` were floor-encoded.
    function depositRemainder(uint256 amount) external pure returns (uint256) {
        return SCHEME.remainder(amount);
    }

    /// True when `amount` is step-aligned (no precision loss).
    function isDepositLossless(uint256 amount) external pure returns (bool) {
        return SCHEME.isLossless(amount);
    }

    /// Snap `amount` down to the nearest step boundary.
    function floorDeposit(uint256 amount) external pure returns (uint256) {
        return SCHEME.floor(amount);
    }

    /// Snap `amount` up to the nearest step boundary.
    function ceilDeposit(uint256 amount) external pure returns (uint256) {
        return SCHEME.ceil(amount);
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

Run the showcase suite with gas report:

```bash
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
