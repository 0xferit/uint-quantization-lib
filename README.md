# uint-quantization-lib

[![Staking Case: Gas Usage Reduction](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-savings.json)](test/showcase/ShowcaseGas.t.sol)
[![Extreme Case: Gas Usage Reduction](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/extreme-savings.json)](test/showcase/ShowcaseGas.t.sol)

On-chain values routinely carry more resolution than the protocol needs, but storage charges for every bit you store, not every bit you use. Unnecessary resolution widens structs, fills extra slots, and costs 20,000 gas per cold write. You do not have to pay for resolution you do not use.

This library quantizes `uint256` values via right-shift, packing more fields per storage slot and cutting gas on every write.

**Quick start:**

```solidity
import {Quant, UintQuantizationLib} from "uint-quantization-lib/src/UintQuantizationLib.sol";

Quant private immutable SCHEME = UintQuantizationLib.create(32, 24);

uint24 stored = uint24(SCHEME.encode(largeValue)); // quantize
uint256 restored = SCHEME.decode(stored); // restore
```

## Installation

```bash
forge soldeer install uint-quantization-lib
```

## Solidity API

Library: `UintQuantizationLib` (`src/UintQuantizationLib.sol`). Import both the `Quant` type and the
library as shown in the [usage example](#solidity-usage) below.

Because the source file declares `using UintQuantizationLib for Quant global`, importers get method-call
syntax automatically without a local `using` statement.

### Type layout

The `Quant` value type is a `uint16` with the following bit layout:

| Bits | Field | Notes |
|---|---|---|
| 0-7 | `discardedBitWidth` | LSBs discarded during encoding |
| 8-15 | `encodedBitWidth` | Bit-width of the encoded value |

### API

| Function | Description |
|---|---|
| `UintQuantizationLib.create(discardedBitWidth, encodedBitWidth)` | Creates a `Quant` scheme. Reverts with `BadConfig` on invalid parameters. |
| `q.discardedBitWidth()` | Number of low bits discarded during encoding (set at creation). |
| `q.encodedBitWidth()` | Bit-width of the encoded value (set at creation). |
| `q.encode(value)` | Compresses `value` by discarding the low bits (floor). Reverts with `Overflow` if `value > max(q)`. |
| `q.encode(value, true)` | Same as `encode(value)`, but also reverts with `NotAligned` if `value` is not step-aligned. |
| `q.decode(encoded)` | Restores `encoded` back to the original scale. Discarded bits are restored as zeros (lower bound). |
| `q.decodeMax(encoded)` | Like `decode`, but fills discarded bits with ones (upper bound within the step). |
| `q.isValid()` | True if `q` satisfies the invariants enforced by `create`. Use to validate hand-wrapped `Quant` values. |
| `q.fits(value)` | True if `value` fits within the scheme's representable range. |
| `q.fitsEncoded(encoded)` | True if `encoded` is within the valid range for decoding (`encoded < 2^encodedBitWidth`). |
| `q.floor(value)` | Rounds `value` down to the nearest step boundary. |
| `q.ceil(value)` | Rounds `value` up to the nearest step boundary. Reverts with `CeilOverflow` when rounding up would exceed `type(uint256).max`. |
| `q.remainder(value)` | Resolution lost if `value` were floor-encoded (`value mod stepSize`). |
| `q.isAligned(value)` | True if `value` is step-aligned (no resolution loss on encode). |
| `q.stepSize()` | Smallest non-zero value the scheme can represent (`2^discardedBitWidth`). |
| `q.max()` | Largest value the scheme can represent: `(2^encodedBitWidth - 1) << discardedBitWidth`. |

### Errors

```solidity
error BadConfig(uint256 discardedBitWidth, uint256 encodedBitWidth);
error Overflow(uint256 value, uint256 max);
error NotAligned(uint256 value, uint256 stepSize);
error CeilOverflow(uint256 value);
```

### Solidity usage

```solidity
import {Quant, UintQuantizationLib} from "uint-quantization-lib/src/UintQuantizationLib.sol";

contract StakingVault {
    Quant private immutable SCHEME = UintQuantizationLib.create(16, 96);

    mapping(address => uint96) internal stakes;

    /// Floor-encodes msg.value and stores the quantized amount.
    function stake() external payable {
        require(SCHEME.fits(msg.value), "amount exceeds scheme max");
        stakes[msg.sender] = uint96(SCHEME.encode(msg.value));
    }

    /// Strict mode: reverts if msg.value is not step-aligned.
    function stakeExact() external payable {
        stakes[msg.sender] = uint96(SCHEME.encode(msg.value, true));
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

    /// Minimum granularity: values must be multiples of this for precise encoding.
    function depositGranularity() external pure returns (uint256) {
        return SCHEME.stepSize();
    }

    /// Bits that would be lost if `amount` were floor-encoded.
    function depositRemainder(uint256 amount) external pure returns (uint256) {
        return SCHEME.remainder(amount);
    }

    /// True when `amount` is step-aligned (no resolution loss).
    function isDepositAligned(uint256 amount) external pure returns (bool) {
        return SCHEME.isAligned(amount);
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

> `encode(value)` and `encode(value, true)` return `uint256` due to Solidity type constraints. The encoded
> result is guaranteed to fit in `2^encodedBitWidth - 1`, so store it using the matching `uintN` for
> your scheme (for example, `uint16` for `encodedBitWidth=16`, `uint24` for `encodedBitWidth=24`). Using a
> smaller type will silently truncate.

## Which encode function should I use?

> - `encode(value)` — Floor encoding with overflow check. Reverts when the value exceeds `max(q)`.
> - `encode(value, true)` — Strict mode: reverts on overflow or when any resolution would be lost.

Use `encode` when the caller controls or bounds the input and floor truncation is acceptable.
Use `encode(value, true)` when exactness is a protocol requirement (e.g., the transaction should revert
rather than silently truncate the value).

## Showcase and gas savings

Showcase contracts under `src/showcase/` use `UintQuantizationLib` and compare:

- Real-life example (production-style ETH staking):
  raw path uses realistic packed fields by default (`uint128 amount`, `uint64` timestamps, `bool active`)
  in `RawETHStakingShowcase`, while the quantized path further reduces stake amount into `uint96`
  in `QuantizedETHStakingShowcase`.
- Extreme example (upper-bound packing showcase):
  raw path stores 12 full-width `uint256` values (`RawExtremePackingShowcase`),
  quantized path packs all 12 into 1 slot (`QuantizedExtremePackingShowcase`).

This demonstrates where quantization creates real gas savings: fewer storage writes and denser
state layout.

The staking showcase intentionally exercises the full API surface:
- `stake()` uses floor encoding (`encode`). This is intentionally lossy: the remainder stays in the contract as unrecoverable dust.
- `stakeExact()` uses strict encoding (`encode(value, true)`). Reverts if the value is not step-aligned, guaranteeing lossless round-trips.
- `unstake()` uses `decode`.
- `maxDeposit()`, `stakeRemainder()`, and `isStakeAligned()` expose
  `max`, `remainder`, and `isAligned` for frontend UX.

Benchmark assertions live in `test/showcase/ShowcaseGas.t.sol`.

Run the showcase suite with gas report:

```bash
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

## License

MIT (see SPDX headers in source files).

## Author

[0xferit](https://github.com/0xferit) — ferit@cryptolab.net
