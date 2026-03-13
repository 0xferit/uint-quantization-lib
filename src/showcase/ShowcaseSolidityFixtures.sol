// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Quant, UintQuantizationLib} from "src/UintQuantizationLib.sol";

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
    error QuantizedETHStakingShowcase__ZeroAmount();
    error QuantizedETHStakingShowcase__NoStake();
    error QuantizedETHStakingShowcase__TransferFailed();

    /// @dev Uses `immutable` with `create()` for readability and self-documenting configuration.
    Quant private immutable SCHEME;
    uint64 public constant COOLDOWN = 1 days;

    struct UserStake {
        uint96 amount;
        uint64 stakedAt;
        uint64 cooldownEndsAt;
        bool active;
    }

    mapping(address => UserStake) internal stakes;

    constructor() {
        SCHEME = UintQuantizationLib.create(16, 96);
    }

    function stake() external payable {
        if (msg.value == 0) revert QuantizedETHStakingShowcase__ZeroAmount();
        uint96 encoded = uint96(SCHEME.encode(msg.value));
        stakes[msg.sender] = UserStake({
            amount: encoded,
            stakedAt: uint64(block.timestamp),
            cooldownEndsAt: uint64(block.timestamp + COOLDOWN),
            active: true
        });
    }

    function stakeExact() external payable {
        if (msg.value == 0) revert QuantizedETHStakingShowcase__ZeroAmount();
        uint96 encoded = uint96(SCHEME.encode(msg.value, true));
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

        uint256 amount = SCHEME.decode(s.amount);
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
        return SCHEME.decode(stakes[user].amount);
    }

    function maxDeposit() external view returns (uint256) {
        return SCHEME.max();
    }

    function stakeRemainder(uint256 amount) external view returns (uint256) {
        return SCHEME.remainder(amount);
    }

    function isStakeAligned(uint256 amount) external view returns (bool) {
        return SCHEME.isAligned(amount);
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
    /// @dev Uses `immutable` with `create()` for readability and self-documenting configuration.
    Quant private immutable SCHEME;

    uint256 internal constant LANES = 12;
    uint256 internal constant LANE_MASK = (uint256(1) << 20) - 1;

    uint256 public packedExtreme;

    constructor() {
        SCHEME = UintQuantizationLib.create(8, 20);
    }

    function setExtremeFloor(uint256[12] calldata values) external {
        uint256 p;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = SCHEME.encode(values[i]) & LANE_MASK;
            p |= lane << (i * 20);
        }
        packedExtreme = p;
    }

    function setExtremeStrict(uint256[12] calldata values) external {
        uint256 p;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = SCHEME.encode(values[i], true);
            p |= lane << (i * 20);
        }
        packedExtreme = p;
    }

    function encodedExtreme() external view returns (uint256[12] memory lanes) {
        uint256 p = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            lanes[i] = (p >> (i * 20)) & LANE_MASK;
        }
    }

    function decodeExtremeFloor() external view returns (uint256[12] memory values) {
        uint256 p = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            values[i] = SCHEME.decode((p >> (i * 20)) & LANE_MASK);
        }
    }
}
