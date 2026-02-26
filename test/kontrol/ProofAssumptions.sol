// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

abstract contract ProofAssumptions is Test {
    function _assumeShiftValid(uint256 shift) internal {
        vm.assume(shift > 0 && shift < 256);
    }

    function _assumeTargetBitsValid(uint256 targetBits) internal {
        vm.assume(targetBits > 0 && targetBits < 256);
    }

    function _assumeNoDecodeOverflow(uint256 value, uint256 shift) internal {
        if (shift < 256) {
            vm.assume(value <= (type(uint256).max >> shift) << shift);
        }
    }
}
