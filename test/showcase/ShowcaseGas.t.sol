// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    EXTREME_PACKING_DISCARDED_BITS,
    EXTREME_PACKING_LANES,
    STAKING_SHOWCASE_COOLDOWN,
    QuantizedETHStakingShowcase,
    QuantizedExtremePackingShowcase,
    RawETHStakingShowcase,
    RawExtremePackingShowcase
} from "src/showcase/ShowcaseSolidityFixtures.sol";

/// @dev Matches the quantized deposit ceiling and stores the original amount in one slot with the stake metadata.
contract ExactETHStakingBaseline {
    error ExactETHStakingBaseline__ZeroAmount();
    error ExactETHStakingBaseline__AmountOverflow();
    error ExactETHStakingBaseline__StakeAlreadyActive();

    uint256 private immutable MAX_DEPOSIT;

    struct Stake {
        uint112 amount;
        uint64 stakedAt;
        uint64 cooldownEndsAt;
        bool active;
    }

    mapping(address => Stake) public stakes;

    constructor(uint256 maxDeposit) {
        assert(maxDeposit <= type(uint112).max);
        MAX_DEPOSIT = maxDeposit;
    }

    function stake() external payable {
        if (msg.value == 0) revert ExactETHStakingBaseline__ZeroAmount();
        if (msg.value > MAX_DEPOSIT) revert ExactETHStakingBaseline__AmountOverflow();
        if (stakes[msg.sender].active) revert ExactETHStakingBaseline__StakeAlreadyActive();

        stakes[msg.sender] = Stake({
            amount: uint112(msg.value),
            stakedAt: uint64(block.timestamp),
            cooldownEndsAt: uint64(block.timestamp + STAKING_SHOWCASE_COOLDOWN),
            active: true
        });
    }
}

contract ShowcaseGasTest is Test {
    uint256 internal constant STAKING_SAMPLE_WEI = 163_840_000_000;
    uint256 internal constant EXTREME_SAMPLE_START = 1_000_000;
    uint256 internal constant EXTREME_SAMPLE_SPACING = 30_000;
    uint256 internal constant MIN_REAL_SAVINGS_BPS = 3_200;
    uint256 internal constant BASIS_POINTS_PER_UNIT = 10_000;

    function setUp() public {
        vm.deal(address(this), 1_000_000 ether);
    }

    function test_gas_real_life_solidity_zero_to_nonzero_savings_ge_target() public {
        RawETHStakingShowcase raw = new RawETHStakingShowcase();
        QuantizedETHStakingShowcase floor = new QuantizedETHStakingShowcase();
        QuantizedETHStakingShowcase strict = new QuantizedETHStakingShowcase();
        ExactETHStakingBaseline exact = new ExactETHStakingBaseline(floor.maxDeposit());

        raw.stake{value: STAKING_SAMPLE_WEI}();
        uint256 rawGas = vm.lastCallGas().gasTotalUsed;
        exact.stake{value: STAKING_SAMPLE_WEI}();
        uint256 exactGas = vm.lastCallGas().gasTotalUsed;
        floor.stake{value: STAKING_SAMPLE_WEI}();
        uint256 floorGas = vm.lastCallGas().gasTotalUsed;
        strict.stakeExact{value: STAKING_SAMPLE_WEI}();
        uint256 strictGas = vm.lastCallGas().gasTotalUsed;

        emit log_named_uint("staking raw gas", rawGas);
        emit log_named_uint("staking exact uint112 gas", exactGas);
        emit log_named_uint("staking floor gas", floorGas);
        emit log_named_uint("staking strict gas", strictGas);
        emit log_named_uint("staking strict savings bps", _savingsBps(rawGas, strictGas));

        (uint112 exactAmount,,,) = exact.stakes(address(this));
        assertEq(exactAmount, STAKING_SAMPLE_WEI);
        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_REAL_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_REAL_SAVINGS_BPS);
    }

    function test_exactStake_enforcesDepositLimitsAndActiveStake() public {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        uint256 cap = quantized.maxDeposit();
        ExactETHStakingBaseline exact = new ExactETHStakingBaseline(cap);
        vm.deal(address(this), cap + 1);

        vm.expectRevert(ExactETHStakingBaseline.ExactETHStakingBaseline__ZeroAmount.selector);
        exact.stake();

        vm.expectRevert(ExactETHStakingBaseline.ExactETHStakingBaseline__AmountOverflow.selector);
        exact.stake{value: cap + 1}();

        exact.stake{value: cap}();
        (uint112 amount,,,) = exact.stakes(address(this));
        assertEq(amount, cap);

        vm.expectRevert(ExactETHStakingBaseline.ExactETHStakingBaseline__StakeAlreadyActive.selector);
        exact.stake{value: 1}();
    }

    /// @notice Reports gas for the twelve-to-one slot comparison.
    function test_gas_extreme_solidity_zero_to_nonzero_logs() public {
        RawExtremePackingShowcase raw = new RawExtremePackingShowcase();
        QuantizedExtremePackingShowcase floor = new QuantizedExtremePackingShowcase();
        QuantizedExtremePackingShowcase strict = new QuantizedExtremePackingShowcase();

        uint256[EXTREME_PACKING_LANES] memory values;
        for (uint256 i; i < values.length; ++i) {
            values[i] = (EXTREME_SAMPLE_START - i * EXTREME_SAMPLE_SPACING) << EXTREME_PACKING_DISCARDED_BITS;
        }

        raw.setExtremeRaw(values);
        uint256 rawGas = vm.lastCallGas().gasTotalUsed;
        floor.setExtremeFloor(values);
        uint256 floorGas = vm.lastCallGas().gasTotalUsed;
        strict.setExtremeStrict(values);
        uint256 strictGas = vm.lastCallGas().gasTotalUsed;

        emit log_named_uint("extreme raw gas", rawGas);
        emit log_named_uint("extreme floor gas", floorGas);
        emit log_named_uint("extreme strict gas", strictGas);
        emit log_named_uint("extreme strict savings bps", _savingsBps(rawGas, strictGas));

        uint256[EXTREME_PACKING_LANES] memory floorValues = floor.decodeExtremeFloor();
        uint256[EXTREME_PACKING_LANES] memory strictValues = strict.decodeExtremeFloor();
        for (uint256 i; i < values.length; ++i) {
            assertEq(floorValues[i], values[i]);
            assertEq(strictValues[i], values[i]);
        }
    }

    function _savingsBps(uint256 rawGas, uint256 quantizedGas) internal pure returns (uint256) {
        return ((rawGas - quantizedGas) * BASIS_POINTS_PER_UNIT) / rawGas;
    }
}
