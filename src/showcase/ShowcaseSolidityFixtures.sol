// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

/// @notice Production-style ETH staking baseline with default Solidity struct packing.
contract RawETHStakingShowcase {
    error RawETHStakingShowcase__ZeroAmount();
    error RawETHStakingShowcase__AmountOverflow();
    error RawETHStakingShowcase__NoStake();
    error RawETHStakingShowcase__TransferFailed();

    uint64 public constant COOLDOWN = 1 days;

    struct UserStakeRaw {
        uint128 amount;
        uint64 stakedAt;
        uint64 cooldownEndsAt;
        bool active;
    }

    mapping(address => UserStakeRaw) public stakes;

    function stake() external payable {
        if (msg.value == 0) revert RawETHStakingShowcase__ZeroAmount();
        if (msg.value > type(uint128).max) revert RawETHStakingShowcase__AmountOverflow();

        stakes[msg.sender] = UserStakeRaw({
            amount: uint128(msg.value),
            stakedAt: uint64(block.timestamp),
            cooldownEndsAt: uint64(block.timestamp + COOLDOWN),
            active: true
        });
    }

    function unstake() external {
        UserStakeRaw memory s = stakes[msg.sender];
        if (!s.active) revert RawETHStakingShowcase__NoStake();

        delete stakes[msg.sender];

        (bool ok,) = msg.sender.call{value: s.amount}("");
        if (!ok) revert RawETHStakingShowcase__TransferFailed();
    }
}

/// @notice Storage-optimized ETH staking showcase operating on an already packed struct.
contract QuantizedETHStakingShowcase {
    using UintQuantizationLib for uint256;

    error QuantizedETHStakingShowcase__ZeroAmount();
    error QuantizedETHStakingShowcase__NoStake();
    error QuantizedETHStakingShowcase__TransferFailed();

    uint256 public constant SHIFT = 16;
    uint256 public constant AMOUNT_BITS = 96;
    uint64 public constant COOLDOWN = 1 days;

    struct UserStake {
        uint96 amount;
        uint64 stakedAt;
        uint64 cooldownEndsAt;
        bool active;
    }

    mapping(address => UserStake) internal stakes;

    function stake() external payable {
        if (msg.value == 0) revert QuantizedETHStakingShowcase__ZeroAmount();
        uint96 encoded = uint96(msg.value.encodeChecked(SHIFT, AMOUNT_BITS));
        stakes[msg.sender] = UserStake({
            amount: encoded,
            stakedAt: uint64(block.timestamp),
            cooldownEndsAt: uint64(block.timestamp + COOLDOWN),
            active: true
        });
    }

    function stakeExact() external payable {
        if (msg.value == 0) revert QuantizedETHStakingShowcase__ZeroAmount();
        uint96 encoded = uint96(msg.value.encodeLosslessChecked(SHIFT, AMOUNT_BITS));
        stakes[msg.sender] = UserStake({
            amount: encoded,
            stakedAt: uint64(block.timestamp),
            cooldownEndsAt: uint64(block.timestamp + COOLDOWN),
            active: true
        });
    }

    function unstake() external {
        UserStake memory s = stakes[msg.sender];
        if (!s.active) revert QuantizedETHStakingShowcase__NoStake();

        uint256 amount = uint256(s.amount).decode(SHIFT);
        delete stakes[msg.sender];

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert QuantizedETHStakingShowcase__TransferFailed();
    }

    function encodedStake(address user)
        external
        view
        returns (uint96 amount, uint64 stakedAt, uint64 cooldownEndsAt, bool active)
    {
        UserStake memory s = stakes[user];
        return (s.amount, s.stakedAt, s.cooldownEndsAt, s.active);
    }

    function getStake(address user) external view returns (uint256) {
        return uint256(stakes[user].amount).decode(SHIFT);
    }

    function maxDeposit() external pure returns (uint256) {
        return UintQuantizationLib.maxRepresentable(SHIFT, AMOUNT_BITS);
    }


    function stakeRemainder(uint256 amount) external pure returns (uint256) {
        return amount.remainder(SHIFT);
    }

    function isStakeLossless(uint256 amount) external pure returns (bool) {
        return amount.isLossless(SHIFT);
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


}
