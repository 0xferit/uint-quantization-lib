// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

/// @notice Thin harness that exposes library functions via `using-for` so tests call them on
///         values rather than through the library name directly.
contract UintQuantizationHarness {
    using UintQuantizationLib for uint256;

    function encode(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encode(shift);
    }

    function encodeCeil(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encodeCeil(shift);
    }

    function decode(uint256 compressed, uint256 shift) external pure returns (uint256) {
        return compressed.decode(shift);
    }

    function decodeCeil(uint256 compressed, uint256 shift) external pure returns (uint256) {
        return compressed.decodeCeil(shift);
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

    function encodeCeilChecked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeCeilChecked(shift, targetBits);
    }

    function encodeLossless(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encodeLossless(shift);
    }

    function encodeLosslessChecked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeLosslessChecked(shift, targetBits);
    }
}

/// @notice Fast concrete regression checks. Mathematical completeness is handled by Kontrol proofs.
contract UintQuantizationLibSmokeTest is Test {
    UintQuantizationHarness harness;

    uint256 private constant SHIFT_32 = 32;

    function setUp() public {
        harness = new UintQuantizationHarness();
    }

    function test_encode_decode_roundTrip_clearsLowBits() public view {
        uint256 value = 1_000_000_000_001;
        uint256 compressed = harness.encode(value, SHIFT_32);
        uint256 restored = harness.decode(compressed, SHIFT_32);
        assertEq(restored, value & ~uint256(type(uint32).max));
    }

    function test_decodeCeil_decode_boundsOriginal() public view {
        uint256 value = (uint256(5) << SHIFT_32) + 999;
        uint256 compressed = harness.encode(value, SHIFT_32);
        assertLe(harness.decode(compressed, SHIFT_32), value);
        assertGe(harness.decodeCeil(compressed, SHIFT_32), value);
    }

    function test_isLossless_true_whenStepAligned() public view {
        uint256 value = uint256(123) << SHIFT_32;
        assertTrue(harness.isLossless(value, SHIFT_32));
    }

    function test_isLossless_false_whenInexact() public view {
        uint256 value = (uint256(123) << SHIFT_32) + 1;
        assertFalse(harness.isLossless(value, SHIFT_32));
    }

    function test_encodeLossless_exact_succeeds() public view {
        uint256 value = uint256(321) << SHIFT_32;
        assertEq(harness.encodeLossless(value, SHIFT_32), 321);
    }

    function test_encodeLossless_inexact_reverts() public {
        uint256 value = (uint256(321) << SHIFT_32) + 7;
        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__InexactInput.selector,
                value,
                SHIFT_32,
                uint256(7)
            )
        );
        harness.encodeLossless(value, SHIFT_32);
    }

    function test_encodeCeil_shiftTooLarge_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__InvalidShift.selector, uint256(256))
        );
        harness.encodeCeil(42, 256);
    }

    function test_stepSize_shiftTooLarge_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__InvalidShift.selector, uint256(256))
        );
        harness.stepSize(256);
    }

    function test_remainder_shiftTooLarge_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__InvalidShift.selector, uint256(256))
        );
        harness.remainder(42, 256);
    }

    function test_encodeLossless_shiftTooLarge_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__InvalidShift.selector, uint256(256))
        );
        harness.encodeLossless(1 << 8, 256);
    }

    function test_maxRepresentable_targetBitsTooLarge_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(256))
        );
        harness.maxRepresentable(0, 256);
    }

    function test_maxRepresentable_shiftPlusTargetAddOverflow_revertsWithCustomError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(type(uint256).max), uint256(256)
            )
        );
        harness.maxRepresentable(type(uint256).max, 1);
    }

    function test_encodeChecked_targetBits256_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(256))
        );
        harness.encodeChecked(1, 0, 256);
    }

    function test_encodeCeilChecked_targetBits256_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(256))
        );
        harness.encodeCeilChecked(1, 0, 256);
    }

    function test_encodeLosslessChecked_targetBits256_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(256))
        );
        harness.encodeLosslessChecked(1 << 8, 8, 256);
    }

    function test_encodeCeilChecked_encodePassesCeilFails_reverts() public {
        uint256 value = (uint256(type(uint8).max) << 8) + 1;
        assertEq(harness.encodeChecked(value, 8, 8), type(uint8).max);
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(8))
        );
        harness.encodeCeilChecked(value, 8, 8);
    }

    function test_encodeChecked_shiftGte256_returnsZeroLikeEncode() public view {
        assertEq(harness.encode(123_456, 300), 0);
        assertEq(harness.encodeChecked(123_456, 300, 8), 0);
    }

    function testFuzz_decode_encode_is_lower_bound(uint256 value, uint8 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        assertLe(decoded, value);
    }

    function testFuzz_decode_ceil_bounds_original_when_shift_valid(uint256 value, uint8 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 lower = harness.decode(encoded, shift);
        uint256 upper = harness.decodeCeil(encoded, shift);
        assertLe(lower, value);
        assertLe(value, upper);
    }

    function testFuzz_remainder_identity_matches_decode_delta(uint256 value, uint8 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        uint256 rem = harness.remainder(value, shift);
        assertEq(rem, value - decoded);
    }
}
