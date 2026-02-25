// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

/// @notice Baseline showcase that stores two full-width values in two slots.
contract RawUintPairStorageShowcase {
    uint256 public valueA;
    uint256 public valueB;

    function setPair(uint256 a, uint256 b) external {
        valueA = a;
        valueB = b;
    }
}

/// @notice Quantized showcase that stores two compressed values in one slot.
contract QuantizedUintPairStorageShowcase {
    using UintQuantizationLib for uint256;

    uint256 internal constant SHIFT = 40;
    uint256 internal constant WIDTH = 56;
    uint256 internal constant LANE_MASK = (uint256(1) << WIDTH) - 1;

    uint256 public packedPair;

    function setPairFloor(uint256 a, uint256 b) external {
        uint256 encodedA = a.encodeChecked(SHIFT, WIDTH);
        uint256 encodedB = b.encodeChecked(SHIFT, WIDTH);
        packedPair = encodedA | (encodedB << WIDTH);
    }

    function setPairStrict(uint256 a, uint256 b) external {
        uint256 encodedA = a.encodeLosslessChecked(SHIFT, WIDTH);
        uint256 encodedB = b.encodeLosslessChecked(SHIFT, WIDTH);
        packedPair = encodedA | (encodedB << WIDTH);
    }

    function encodedPair() external view returns (uint256 encodedA, uint256 encodedB) {
        encodedA = packedPair & LANE_MASK;
        encodedB = (packedPair >> WIDTH) & LANE_MASK;
    }

    function decodeFloor() external view returns (uint256 lowerA, uint256 lowerB) {
        uint256 encodedA = packedPair & LANE_MASK;
        uint256 encodedB = (packedPair >> WIDTH) & LANE_MASK;
        lowerA = encodedA.decode(SHIFT);
        lowerB = encodedB.decode(SHIFT);
    }

    function decodeCeil() external view returns (uint256 upperA, uint256 upperB) {
        uint256 encodedA = packedPair & LANE_MASK;
        uint256 encodedB = (packedPair >> WIDTH) & LANE_MASK;
        upperA = encodedA.decodeCeil(SHIFT);
        upperB = encodedB.decodeCeil(SHIFT);
    }
}
