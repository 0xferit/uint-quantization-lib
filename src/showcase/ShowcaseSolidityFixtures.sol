// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Quant, UintQuantizationLib} from "../UintQuantizationLib.sol";

uint64 constant STAKING_SHOWCASE_COOLDOWN = 1 days;

/// @notice Ether staking benchmark fixture with default Solidity struct packing.
/// @dev Each address can hold one active stake. Withdrawal is available when its cooldown expires.
contract RawETHStakingShowcase {
    error RawETHStakingShowcase__ZeroAmount();
    error RawETHStakingShowcase__AmountOverflow();
    error RawETHStakingShowcase__NoStake();
    error RawETHStakingShowcase__TransferFailed();

    uint64 public constant COOLDOWN = STAKING_SHOWCASE_COOLDOWN;

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
        require(!stakes[msg.sender].active, "stake already active");

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

        require(block.timestamp >= s.cooldownEndsAt, "stake cooldown");

        delete stakes[msg.sender];

        (bool ok,) = msg.sender.call{value: s.amount}("");
        if (!ok) revert RawETHStakingShowcase__TransferFailed();
    }
}

/// @notice Ether staking benchmark fixture with a quantized amount packed beside the timestamps and active flag.
/// @dev Each address can hold one active stake. Withdrawal is available when its cooldown expires.
contract QuantizedETHStakingShowcase {
    error QuantizedETHStakingShowcase__ZeroAmount();
    error QuantizedETHStakingShowcase__NoStake();
    error QuantizedETHStakingShowcase__TransferFailed();

    /// @dev Uses `immutable` with `create()` for readability and self-documenting configuration.
    Quant private immutable SCHEME;
    uint64 public constant COOLDOWN = STAKING_SHOWCASE_COOLDOWN;

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

    /// @notice Floor-encodes a positive deposit. The discarded remainder stays in the contract as unrecoverable
    ///         dust. A deposit smaller than one step opens a stake with zero withdrawable value.
    function stake() external payable {
        _stake(false);
    }

    /// @notice Stakes a positive deposit aligned to the scheme's step size without rounding.
    function stakeExact() external payable {
        _stake(true);
    }

    function _stake(bool exact) private {
        if (msg.value == 0) revert QuantizedETHStakingShowcase__ZeroAmount();
        require(!stakes[msg.sender].active, "stake already active");

        uint96 encoded = uint96(SCHEME.encode(msg.value, exact));
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
        require(block.timestamp >= s.cooldownEndsAt, "stake cooldown");

        uint256 amount = SCHEME.decodeUnchecked(s.amount);
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
        return SCHEME.decodeUnchecked(stakes[user].amount);
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

uint256 constant EXTREME_PACKING_LANES = 12;
uint256 constant EXTREME_PACKING_DISCARDED_BITS = 8;

/// @notice Deliberately verbose baseline used to demonstrate upper-bound packing gains.
contract RawExtremePackingShowcase {
    uint256[EXTREME_PACKING_LANES] public rawValues;

    function setExtremeRaw(uint256[EXTREME_PACKING_LANES] calldata values) external {
        for (uint256 i; i < values.length; ++i) {
            rawValues[i] = values[i];
        }
    }
}

/// @notice Extreme packing benchmark fixture storing all quantized values in one slot.
/// @dev Both setters enforce the lane range. The floor setter rounds down and the strict setter requires alignment.
contract QuantizedExtremePackingShowcase {
    /// @dev Uses `immutable` with `create()` for readability and self-documenting configuration.
    Quant private immutable SCHEME;

    uint256 internal constant LANES = EXTREME_PACKING_LANES;
    uint256 private constant LANE_WIDTH = 20;
    uint256 internal constant LANE_MASK = (uint256(1) << LANE_WIDTH) - 1;

    uint256 public packedExtreme;

    constructor() {
        SCHEME = UintQuantizationLib.create(EXTREME_PACKING_DISCARDED_BITS, LANE_WIDTH);
    }

    function setExtremeFloor(uint256[EXTREME_PACKING_LANES] calldata values) external {
        uint256 packed = 0;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = SCHEME.encode(values[i]);
            packed |= lane << (i * LANE_WIDTH);
        }
        packedExtreme = packed;
    }

    function setExtremeStrict(uint256[EXTREME_PACKING_LANES] calldata values) external {
        uint256 packed = 0;
        for (uint256 i; i < LANES; ++i) {
            uint256 lane = SCHEME.encode(values[i], true);
            packed |= lane << (i * LANE_WIDTH);
        }
        packedExtreme = packed;
    }

    function encodedExtreme() external view returns (uint256[EXTREME_PACKING_LANES] memory lanes) {
        uint256 packed = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            lanes[i] = (packed >> (i * LANE_WIDTH)) & LANE_MASK;
        }
    }

    function decodeExtremeFloor() external view returns (uint256[EXTREME_PACKING_LANES] memory values) {
        uint256 packed = packedExtreme;
        for (uint256 i; i < LANES; ++i) {
            values[i] = SCHEME.decodeUnchecked((packed >> (i * LANE_WIDTH)) & LANE_MASK);
        }
    }
}
