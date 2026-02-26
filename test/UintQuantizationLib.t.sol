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

    function test_encodeLosslessChecked_targetBits256_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(UintQuantizationLib.UintQuantizationLib__Overflow.selector, uint256(256), uint256(256))
        );
        harness.encodeLosslessChecked(1 << 8, 8, 256);
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

    function testFuzz_decode_bounds_original_when_shift_valid(uint256 value, uint8 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        assertLe(decoded, value);
    }

    function testFuzz_remainder_identity_matches_decode_delta(uint256 value, uint8 shift) public view {
        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        uint256 rem = harness.remainder(value, shift);
        assertEq(rem, value - decoded);
    }

    /// @notice Fuzz test for lossless round-trip property:
    ///         if isLossless(v, s) then decode(encode(v, s), s) == v
    ///         Mirrors Kontrol proof: prove_encode_lossless_exact_round_trip
    function testFuzz_lossless_round_trip_is_exact(uint256 value, uint8 shift) public view {
        // Only test when value is lossless (step-aligned)
        if (!harness.isLossless(value, shift)) {
            return;
        }

        uint256 encoded = harness.encode(value, shift);
        uint256 decoded = harness.decode(encoded, shift);
        assertEq(decoded, value, "Lossless round-trip should preserve exact value");
    }

    /// @notice Fuzz test for encode monotonicity:
    ///         v1 <= v2 implies encode(v1, s) <= encode(v2, s)
    ///         This ensures the encoding preserves ordering of values
    function testFuzz_encode_monotonicity(uint256 value1, uint256 value2, uint8 shift) public view {
        // Ensure value1 <= value2 for the test
        if (value1 > value2) {
            (value1, value2) = (value2, value1);
        }

        uint256 encoded1 = harness.encode(value1, shift);
        uint256 encoded2 = harness.encode(value2, shift);

        assertLe(encoded1, encoded2, "Encode should preserve value ordering");
    }

    /// @notice Fuzz test for encodeChecked overflow safety:
    ///         When value fits in targetBits after shift, encodeChecked succeeds
    ///         When value exceeds targetBits capacity, encodeChecked reverts
    function testFuzz_encode_checked_overflow_behavior(uint256 value, uint8 shift, uint8 targetBits) public {
        // targetBits must be < 256 for encodeChecked to not revert immediately
        vm.assume(targetBits < 256);

        uint256 encoded = value >> shift;

        if (encoded >> targetBits != 0) {
            // Value exceeds targetBits capacity, should revert
            vm.expectRevert(
                abi.encodeWithSelector(
                    UintQuantizationLib.UintQuantizationLib__Overflow.selector,
                    encoded,
                    targetBits
                )
            );
            harness.encodeChecked(value, shift, targetBits);
        } else {
            // Value fits in targetBits, should succeed
            uint256 result = harness.encodeChecked(value, shift, targetBits);
            assertEq(result, encoded, "encodeChecked should return correct encoded value");
        }
    }
}
