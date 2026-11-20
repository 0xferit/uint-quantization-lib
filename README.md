# uint-quantization-lib

Quantize a `uint256` into a smaller field when the application can tolerate rounding down. Gas savings depend on the number of storage slots the enclosing record occupies. A narrower value in a standalone mapping still occupies one slot per key.

## Installation

For a stable import path, configure Soldeer in your project's `foundry.toml` before installing.

```toml
[soldeer]
remappings_version = false
```

```sh
forge soldeer install 'uint-quantization-lib~8.0.0' --config-location foundry
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
[![Exact uint112 and strict uint96 stake gas][staking-equal-range]](test/showcase/ShowcaseGas.t.sol)
[![Extreme packing gas reduction][extreme-savings]](test/showcase/ShowcaseGas.t.sol)

The badges use the repository's default Foundry profile. To reproduce them, run the showcase gas report.

```sh
forge test --match-path test/showcase/ShowcaseGas.t.sol --gas-report -vv
```

### Cancun and projected Glamsterdam savings

Each row shows the gas the sender pays for one successful first write to an already-deployed contract with empty storage. Cancun and Glamsterdam use the same Cancun-compiled bytecode, calldata and attached value. The samples satisfy strict encoding's alignment requirement. Savings are relative to the raw fixture in each group.

| First write | Cancun gas | Cancun saving | Projected Glamsterdam gas | Projected saving |
|---|---:|---:|---:|---:|
| extreme raw | 289,917 | baseline | 1,338,957 | baseline |
| extreme floor | 51,164 | 82.35% | 133,084 | 90.06% |
| extreme strict | 52,859 | 81.77% | 134,779 | 89.93% |
| staking raw | 66,123 | baseline | 242,163 | baseline |
| staking exact uint112 | 43,990 | 33.47% | 132,010 | 45.49% |
| staking floor | 44,313 | 32.98% | 132,333 | 45.35% |
| staking strict | 44,473 | 32.74% | 132,493 | 45.29% |

Extreme packing cuts twelve new slots to one. In the staking fixture, packing cuts the two-slot `uint128` record to one slot. An exact `uint112` also fits in one slot and covers the same deposit range as the quantized `uint96`. It preserves every wei and costs 483 gas less than strict quantization on either fork. Deployment and updates to existing slots have different costs.

The proposed Glamsterdam schedule tested on November 20, 2026 charges 97,920 state gas per newly populated slot in addition to execution gas. The projection uses transaction receipts so it includes both charges. The schedule may change before mainnet activation. [State creation proposal](https://github.com/ethereum/EIPs/blob/b055feec322fbc37e9d77a393a50b3ff56b31c92/EIPS/eip-8037.md) · [State access proposal](https://github.com/ethereum/EIPs/blob/b055feec322fbc37e9d77a393a50b3ff56b31c92/EIPS/eip-8038.md) · [Ethereum Foundation testing update](https://blog.ethereum.org/2026/11/06/glamsterdam-8037-8038)

To reproduce the table from this checkout, use Python 3.10 or later, Foundry 1.8.4 (`forge`, `cast`) and Geth 1.17.10 (`geth`, `evm`) on your path. The build caches the pinned Solidity compiler. The comparison then runs offline.

```sh
forge soldeer install
forge build
python3 scripts/compare-fork-gas.py
```

[Benchmark suite](test/showcase/ShowcaseGas.t.sol) · [MIT license](LICENSE) · [0xferit](https://github.com/0xferit)

[staking-savings]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-savings.json
[staking-equal-range]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/staking-equal-range.json
[extreme-savings]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/0xferit/uint-quantization-lib/gh-badges/.badges/extreme-savings.json
