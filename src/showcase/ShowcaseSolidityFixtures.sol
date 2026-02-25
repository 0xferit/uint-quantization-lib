// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

/// @notice Baseline ERC20-style accounting state using four full-width storage slots.
contract RawERC20StateShowcase {
    uint256 public totalSupply;
    uint256 public treasuryBalance;
    uint256 public feeAccumulator;
    uint256 public nonceCursor;

    function setStateRaw(uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
        external
    {
        totalSupply = _totalSupply;
        treasuryBalance = _treasuryBalance;
        feeAccumulator = _feeAccumulator;
        nonceCursor = _nonceCursor;
    }
}

/// @notice Quantized ERC20-style accounting state packed into one storage slot.
contract QuantizedERC20StateShowcase {
    using UintQuantizationLib for uint256;

    uint256 internal constant SHIFT = 16;
    uint256 internal constant WIDTH = 40;
    uint256 internal constant LANE_MASK = (uint256(1) << WIDTH) - 1;

    uint256 public packedState;

    function setStateFloor(uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
        external
    {
        uint256 e0 = _totalSupply.encodeChecked(SHIFT, WIDTH);
        uint256 e1 = _treasuryBalance.encodeChecked(SHIFT, WIDTH);
        uint256 e2 = _feeAccumulator.encodeChecked(SHIFT, WIDTH);
        uint256 e3 = _nonceCursor.encodeChecked(SHIFT, WIDTH);

        packedState = e0 | (e1 << 40) | (e2 << 80) | (e3 << 120);
    }

    function setStateStrict(uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
        external
    {
        uint256 e0 = _totalSupply.encodeLosslessChecked(SHIFT, WIDTH);
        uint256 e1 = _treasuryBalance.encodeLosslessChecked(SHIFT, WIDTH);
        uint256 e2 = _feeAccumulator.encodeLosslessChecked(SHIFT, WIDTH);
        uint256 e3 = _nonceCursor.encodeLosslessChecked(SHIFT, WIDTH);

        packedState = e0 | (e1 << 40) | (e2 << 80) | (e3 << 120);
    }

    function encodedState()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
    {
        uint256 p = packedState;
        _totalSupply = p & LANE_MASK;
        _treasuryBalance = (p >> 40) & LANE_MASK;
        _feeAccumulator = (p >> 80) & LANE_MASK;
        _nonceCursor = (p >> 120) & LANE_MASK;
    }

    function decodeStateFloor()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
    {
        uint256 p = packedState;
        _totalSupply = (p & LANE_MASK).decode(SHIFT);
        _treasuryBalance = ((p >> 40) & LANE_MASK).decode(SHIFT);
        _feeAccumulator = ((p >> 80) & LANE_MASK).decode(SHIFT);
        _nonceCursor = ((p >> 120) & LANE_MASK).decode(SHIFT);
    }

    function decodeStateCeil()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
    {
        uint256 p = packedState;
        _totalSupply = (p & LANE_MASK).decodeCeil(SHIFT);
        _treasuryBalance = ((p >> 40) & LANE_MASK).decodeCeil(SHIFT);
        _feeAccumulator = ((p >> 80) & LANE_MASK).decodeCeil(SHIFT);
        _nonceCursor = ((p >> 120) & LANE_MASK).decodeCeil(SHIFT);
    }
}

/// @notice Deliberately verbose baseline used to demonstrate upper-bound packing gains.
contract RawExtremePackingShowcase {
    uint256[12] public rawValues;

    function setExtremeRaw(uint256[12] calldata values) external {
        for (uint256 i; i < 12; ++i) {
            rawValues[i] = values[i];
        }
    }
}

/// @notice Extreme packing showcase: 12 quantized values packed into one slot.
///         `setExtremeFloor` intentionally favors throughput over safety and does not
///         enforce lane-width bounds (it masks to width). Use strict mode for safety.
contract QuantizedExtremePackingShowcase {
    using UintQuantizationLib for uint256;

    uint256 internal constant SHIFT = 8;
    uint256 internal constant WIDTH = 20;
    uint256 internal constant LANES = 12;
    uint256 internal constant LANE_MASK = (uint256(1) << WIDTH) - 1;

    uint256 public packedExtreme;

    function setExtremeFloor(uint256[12] calldata values) external {
        uint256 p;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = values[i].encode(SHIFT) & LANE_MASK;
            p |= lane << (i * WIDTH);
        }
        packedExtreme = p;
    }

    function setExtremeStrict(uint256[12] calldata values) external {
        uint256 p;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = values[i].encodeLosslessChecked(SHIFT, WIDTH);
            p |= lane << (i * WIDTH);
        }
        packedExtreme = p;
    }

    function encodedExtreme() external view returns (uint256[12] memory lanes) {
        uint256 p = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            lanes[i] = (p >> (i * WIDTH)) & LANE_MASK;
        }
    }

    function decodeExtremeFloor() external view returns (uint256[12] memory values) {
        uint256 p = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            values[i] = ((p >> (i * WIDTH)) & LANE_MASK).decode(SHIFT);
        }
    }

    function decodeExtremeCeil() external view returns (uint256[12] memory values) {
        uint256 p = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            values[i] = ((p >> (i * WIDTH)) & LANE_MASK).decodeCeil(SHIFT);
        }
    }
}
