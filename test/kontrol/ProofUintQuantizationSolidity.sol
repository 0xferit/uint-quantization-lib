// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";
import {ProofAssumptions} from "test/kontrol/ProofAssumptions.sol";

contract UintQuantizationKontrolHarness {
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

contract ProofUintQuantizationSolidity is ProofAssumptions {
    UintQuantizationKontrolHarness internal harness;

    function setUp() public {
        harness = new UintQuantizationKontrolHarness();
    }

    function proof_encode_decode_le_original(uint256 value, uint256 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        assertLe(decoded, value);
    }









    function proof_remainder_lt_step_size(uint256 value, uint256 shift) public {
        _assumeShiftValid(shift);
        uint256 rem = harness.remainder(value, shift);
        uint256 step = harness.stepSize(shift);
        assertLt(rem, step);
    }

    function proof_remainder_identity(uint256 value, uint256 shift) public {
        _assumeShiftValid(shift);
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        uint256 rem = harness.remainder(value, shift);
        assertEq(rem, value - decoded);
    }

    function proof_is_lossless_iff_remainder_zero(uint256 value, uint256 shift) public {
        _assumeShiftValid(shift);
        assertEq(harness.isLossless(value, shift), harness.remainder(value, shift) == 0);
    }

    function proof_encode_lossless_exact_round_trip(uint256 value, uint256 shift) public {
        _assumeShiftValid(shift);
        vm.assume(harness.isLossless(value, shift));
        uint256 encoded = harness.encodeLossless(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        assertEq(decoded, value);
    }

    function proof_encode_lossless_inexact_reverts(uint256 value, uint256 shift) public {
        _assumeShiftValid(shift);
        vm.assume(!harness.isLossless(value, shift));
        _assertInexactRevert(abi.encodeWithSelector(harness.encodeLossless.selector, value, shift));
    }

    function proof_encode_checked_target_bits_256_reverts(uint256 value, uint256 shift) public view {
        _assertOverflowRevert(abi.encodeWithSelector(harness.encodeChecked.selector, value, shift, 256));
    }



    function proof_encode_lossless_checked_target_bits_256_reverts(uint256 value, uint256 shift) public view {
        _assertOverflowRevert(abi.encodeWithSelector(harness.encodeLosslessChecked.selector, value, shift, 256));
    }

    function proof_max_representable_target_bits_256_reverts(uint256 shift) public view {
        _assertOverflowRevert(abi.encodeWithSelector(harness.maxRepresentable.selector, shift, 256));
    }

    function proof_max_representable_excess_bits_revert(uint256 shift, uint256 targetBits) public {
        _assumeTargetBitsValid(targetBits);
        vm.assume(shift > 256 - targetBits);
        _assertOverflowRevert(abi.encodeWithSelector(harness.maxRepresentable.selector, shift, targetBits));
    }

    function proof_max_representable_boundary_is_tight(uint256 shift, uint256 targetBits) public {
        _assumeTargetBitsValid(targetBits);
        vm.assume(shift <= 256 - targetBits);

        uint256 max = harness.maxRepresentable(shift, targetBits);
        uint256 compressed = harness.encodeChecked(max, shift, targetBits);
        uint256 expected = targetBits == 0 ? 0 : (1 << targetBits) - 1;
        assertEq(compressed, expected);
    }

    function _assertOverflowRevert(bytes memory callData) internal view {
        (bool success, bytes memory returndata) = address(harness).staticcall(callData);
        assertFalse(success);
        _assertCustomErrorSelector(returndata, UintQuantizationLib.UintQuantizationLib__Overflow.selector);
    }

    function _assertInexactRevert(bytes memory callData) internal view {
        (bool success, bytes memory returndata) = address(harness).staticcall(callData);
        assertFalse(success);
        _assertCustomErrorSelector(returndata, UintQuantizationLib.UintQuantizationLib__InexactInput.selector);
    }

    function _assertCustomErrorSelector(bytes memory returndata, bytes4 expectedSelector) internal pure {
        assertGe(returndata.length, 4);
        bytes4 actualSelector;
        assembly ("memory-safe") {
            actualSelector := mload(add(returndata, 0x20))
        }
        assertEq(actualSelector, expectedSelector);
    }
}
