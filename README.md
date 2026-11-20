# uint-quantization-lib

Quantize a `uint256` into a smaller field when the application can tolerate rounding down. Gas savings depend on the number of storage slots the enclosing record occupies. A narrower value in a standalone mapping still occupies one slot per key.

## Installation

For a stable import path, configure Soldeer in your project's `foundry.toml` before installing.

```toml
[soldeer]
remappings_version = false
```

```sh
forge soldeer install 'uint-quantization-lib~7.1.0' --config-location foundry
```

## Solidity usage

Each caller records its latest pair of readings in one slot. Both readings use the same scale and can lose up to 255 base units.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Quant, UintQuantizationLib} from "uint-quantization-lib/src/UintQuantizationLib.sol";

contract Readings {
    Quant private immutable SCHEME = UintQuantizationLib.create(8, 128);

    struct Pair {
        uint128 x;
        uint128 y;
    }

    mapping(address => Pair) private readings;

    function record(uint256 x, uint256 y) external {
        readings[msg.sender] = Pair(uint128(SCHEME.encode(x)), uint128(SCHEME.encode(y)));
    }

    function latest(address sensor) external view returns (uint256 x, uint256 y) {
        Pair storage p = readings[sensor];
        return (SCHEME.decode(p.x), SCHEME.decode(p.y));
    }
}
```

## Choosing a scheme

`create(discardedBitWidth, encodedBitWidth)` validates the widths and packs them into a `Quant`. Both widths must fit in a byte, the encoded width must be positive, and their sum must be at most 256. Use `isValid()` for schemes of unknown origin. The default zero scheme is invalid.

- **Floor encoding.** `encode(value)` discards low bits. It checks the original value against `max()` before rounding. Store its result in a Solidity type at least as wide as the encoded width.
- **Exact encoding.** `encode(value, true)` also requires step alignment. Use this mode when discarded units would represent funds owed to a caller.
- **Decoding.** `decode` returns the lower bound and `decodeMax` returns the bucket's upper bound. In the last bucket that upper bound can exceed the largest accepted input. Use unchecked decoding only for a known-valid scheme and encoded value.

[Scheme planner](https://0xferit.github.io/uint-quantization-lib/playground.html) · [Library reference](src/UintQuantizationLib.sol)

## Gas benchmarks

[![Strict stake versus raw uint128][staking-savings]](test/showcase/ShowcaseGas.t.sol)
[![Extreme packing gas reduction][extreme-savings]](test/showcase/ShowcaseGas.t.sol)

The staking fixtures compare a two-slot raw `uint128` record with a one-slot quantized `uint96` record. The extreme-packing fixtures compare twelve raw slots with one packed slot. These contracts are benchmark fixtures.

```sh
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

[Benchmark suite](test/showcase/ShowcaseGas.t.sol) · [MIT license](LICENSE) · [0xferit](https://github.com/0xferit)

[staking-savings]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-savings.json
[extreme-savings]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/extreme-savings.json
