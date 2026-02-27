// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

/// @notice Thin harness that exposes library functions via `using-for` so tests call them on
///         values rather than through the library name directly.
contract UintQuantizationHarness {
    using UintQuantizationLib for uint256;

    function encode(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encode(shift);
    }

    function decode(uint256 compressed, uint256 shift) external pure returns (uint256) {
        return compressed.decode(shift);
    }

    function stepSize(uint256 shift) external pure returns (uint256) {
        return UintQuantizationLib.stepSize(shift);
    }

    function remainder(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.remainder(shift);
    }

    function isLossless(uint256 value, uint256 shift) external pure returns (bool) {
        return UintQuantizationLib.isLossless(value, shift);
    }

    function maxRepresentable(uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return UintQuantizationLib.maxRepresentable(shift, targetBits);
    }

    function encodeChecked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeChecked(shift, targetBits);
    }

    function encodeLossless(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encodeLossless(shift);
    }

    function encodeLosslessChecked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeLosslessChecked(shift, targetBits);
    }
}
