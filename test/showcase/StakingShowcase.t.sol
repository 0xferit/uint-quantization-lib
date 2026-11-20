// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {QuantizedETHStakingShowcase, RawETHStakingShowcase} from "src/showcase/ShowcaseSolidityFixtures.sol";

contract StakingShowcaseTest is Test {
    RawETHStakingShowcase private raw;
    QuantizedETHStakingShowcase private quantized;
    uint256 private step;

    receive() external payable {}

    function setUp() public {
        raw = new RawETHStakingShowcase();
        quantized = new QuantizedETHStakingShowcase();
        step = quantized.stakeRemainder(type(uint256).max) + 1;
        vm.deal(address(this), 1 ether);
    }

    function test_rawStake_rejectsAnotherDepositUntilWithdrawal() public {
        raw.stake{value: step}();
        vm.warp(vm.getBlockTimestamp() + raw.COOLDOWN());

        vm.expectRevert(RawETHStakingShowcase.RawETHStakingShowcase__StakeAlreadyActive.selector);
        raw.stake{value: step}();

        raw.unstake();
        raw.stake{value: step}();
    }

    function test_quantizedStake_rejectsAnotherDepositThroughEitherMethod() public {
        quantized.stakeExact{value: step}();
        vm.warp(vm.getBlockTimestamp() + quantized.COOLDOWN());

        vm.expectRevert(QuantizedETHStakingShowcase.QuantizedETHStakingShowcase__StakeAlreadyActive.selector);
        quantized.stake{value: step}();
        vm.expectRevert(QuantizedETHStakingShowcase.QuantizedETHStakingShowcase__StakeAlreadyActive.selector);
        quantized.stakeExact{value: step}();

        uint256 balanceBefore = address(this).balance;
        quantized.unstake();
        assertEq(address(this).balance - balanceBefore, step);
        quantized.stake{value: step}();
    }

    function test_rawUnstake_rejectsBeforeDeadlineAndPaysAtDeadline() public {
        raw.stake{value: step}();
        uint256 deadline = vm.getBlockTimestamp() + raw.COOLDOWN();
        vm.warp(deadline - 1);

        vm.expectRevert(RawETHStakingShowcase.RawETHStakingShowcase__CooldownActive.selector);
        raw.unstake();

        vm.warp(deadline);
        uint256 balanceBefore = address(this).balance;
        raw.unstake();
        assertEq(address(this).balance - balanceBefore, step);

        vm.expectRevert(RawETHStakingShowcase.RawETHStakingShowcase__NoStake.selector);
        raw.unstake();
    }

    function test_quantizedUnstake_rejectsBeforeDeadlineAndPaysFloorAtDeadline() public {
        uint256 dust = step - 1;
        quantized.stake{value: step + dust}();
        uint256 deadline = vm.getBlockTimestamp() + quantized.COOLDOWN();
        vm.warp(deadline - 1);

        vm.expectRevert(QuantizedETHStakingShowcase.QuantizedETHStakingShowcase__CooldownActive.selector);
        quantized.unstake();

        vm.warp(deadline);
        uint256 balanceBefore = address(this).balance;
        quantized.unstake();
        assertEq(address(this).balance - balanceBefore, step);
        assertEq(address(quantized).balance, dust);

        vm.expectRevert(QuantizedETHStakingShowcase.QuantizedETHStakingShowcase__NoStake.selector);
        quantized.unstake();
    }

    function test_quantizedStake_positiveSubstepDepositIsActive() public {
        quantized.stake{value: step - 1}();

        assertEq(quantized.getStake(address(this)), 0);
        vm.expectRevert(QuantizedETHStakingShowcase.QuantizedETHStakingShowcase__StakeAlreadyActive.selector);
        quantized.stakeExact{value: step}();
    }
}
