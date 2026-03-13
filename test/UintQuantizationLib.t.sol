// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Quant, UintQuantizationLib, Overflow, NotAligned, BadConfig, CeilOverflow} from "src/UintQuantizationLib.sol";

/// @notice Thin harness that exposes library functions via `using-for` so tests call them on
///         `Quant` values rather than through the library name directly.
contract QuantHarness {
    function create(uint256 discardedBitWidth_, uint256 encodedBitWidth_) external pure returns (Quant) {
        return UintQuantizationLib.create(discardedBitWidth_, encodedBitWidth_);
    }

    function discardedBitWidth(Quant q) external pure returns (uint256) {
        return q.discardedBitWidth();
    }

    function encodedBitWidth(Quant q) external pure returns (uint256) {
        return q.encodedBitWidth();
    }

    function stepSize(Quant q) external pure returns (uint256) {
        return q.stepSize();
    }

    function max(Quant q) external pure returns (uint256) {
        return q.max();
    }

    function encode(Quant q, uint256 value) external pure returns (uint256) {
        return q.encode(value);
    }

    function encode(Quant q, uint256 value, bool precise) external pure returns (uint256) {
        return q.encode(value, precise);
    }

    function decode(Quant q, uint256 encoded) external pure returns (uint256) {
        return q.decode(encoded);
    }

    function decodeMax(Quant q, uint256 encoded) external pure returns (uint256) {
        return q.decodeMax(encoded);
    }

    function decodeUnchecked(Quant q, uint256 encoded) external pure returns (uint256) {
        return q.decodeUnchecked(encoded);
    }

    function decodeMaxUnchecked(Quant q, uint256 encoded) external pure returns (uint256) {
        return q.decodeMaxUnchecked(encoded);
    }

    function remainder(Quant q, uint256 value) external pure returns (uint256) {
        return q.remainder(value);
    }

    function isAligned(Quant q, uint256 value) external pure returns (bool) {
        return q.isAligned(value);
    }

    function isValid(Quant q) external pure returns (bool) {
        return q.isValid();
    }

    function fits(Quant q, uint256 value) external pure returns (bool) {
        return q.fits(value);
    }

    function fitsEncoded(Quant q, uint256 encoded) external pure returns (bool) {
        return q.fitsEncoded(encoded);
    }

    function floor(Quant q, uint256 value) external pure returns (uint256) {
        return q.floor(value);
    }

    function ceil(Quant q, uint256 value) external pure returns (uint256) {
        return q.ceil(value);
    }
}

/// @notice Fast concrete regression checks. Mathematical completeness is covered by fuzz tests.
contract UintQuantizationLibSmokeTest is Test {
    QuantHarness harness;

    // discardedBitWidth=8, encodedBitWidth=8: stepSize=256, max=65280
    uint256 private constant DISCARDED_8 = 8;
    uint256 private constant ENCODED_8 = 8;

    function setUp() public {
        harness = new QuantHarness();
    }

    // -------------------------------------------------------------------------
    // create: bad config reverts
    // -------------------------------------------------------------------------

    function test_create_discardedBitWidthTooLarge_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(256), uint256(8)));
        harness.create(256, 8);
    }

    function test_create_encodedBitWidthZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(8), uint256(0)));
        harness.create(8, 0);
    }

    function test_create_encodedBitWidth256_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(8), uint256(256)));
        harness.create(8, 256);
    }

    function test_create_sumExceeds256_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(200), uint256(100)));
        harness.create(200, 100);
    }

    // -------------------------------------------------------------------------
    // encode: overflow revert
    // -------------------------------------------------------------------------

    function test_encode_overflow_reverts() public {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        uint256 m = harness.max(q); // 65280
        uint256 value = m + 1; // 65281
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, value, m));
        harness.encode(q, value);
    }

    // -------------------------------------------------------------------------
    // encode (precise=true): overflow and alignment reverts
    // -------------------------------------------------------------------------

    function test_encodePrecise_notAligned_reverts() public {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        uint256 step = harness.stepSize(q); // 256
        uint256 value = step + 1; // 257, not aligned
        vm.expectRevert(abi.encodeWithSelector(NotAligned.selector, value, step));
        harness.encode(q, value, true);
    }

    function test_encodePrecise_aligned_succeeds() public view {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        uint256 step = harness.stepSize(q); // 256
        // 256 is aligned: encode(256, true) == 1
        assertEq(harness.encode(q, step, true), 1);
    }

    // -------------------------------------------------------------------------
    // ceil: concrete (non-aligned)
    // -------------------------------------------------------------------------

    function test_ceil_nonAligned_concrete() public view {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        // 257 is not aligned to 256; next step is 512
        uint256 result = harness.ceil(q, 257);
        assertEq(result, 512);
        assertGe(result, uint256(257));
        assertTrue(harness.isAligned(q, result));
    }

    // -------------------------------------------------------------------------
    // decodeMax: concrete
    // -------------------------------------------------------------------------

    function test_decodeMax_concrete() public view {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        // decodeMax(3) = (3 << 8) | 255 = 768 | 255 = 1023
        uint256 result = harness.decodeMax(q, 3);
        assertEq(result, 1023);
        assertGe(result, harness.decode(q, 3));
    }

    // -------------------------------------------------------------------------
    // Boundary: discardedBitWidth == 0 (identity / no quantization)
    // -------------------------------------------------------------------------

    function test_discardedBitWidth_zero_identity() public view {
        // discardedBitWidth=0, encodedBitWidth=8: stepSize=1, max=255, encode is identity
        Quant q = harness.create(0, 8);
        assertEq(harness.stepSize(q), 1);
        assertEq(harness.max(q), 255);
        assertEq(harness.encode(q, 200), 200);
        assertEq(harness.decode(q, 200), 200);
        assertTrue(harness.isAligned(q, 200));
        // ceil and floor are identity when discardedBitWidth=0
        assertEq(harness.floor(q, 137), 137);
        assertEq(harness.ceil(q, 137), 137);
    }

    // -------------------------------------------------------------------------
    // Boundary: discardedBitWidth + encodedBitWidth == 256 (full uint256 range)
    // -------------------------------------------------------------------------

    function test_full_uint256_range() public view {
        // discardedBitWidth=128, encodedBitWidth=128: uses the full 256-bit space
        Quant q = harness.create(128, 128);
        uint256 m = harness.max(q);
        // max = (2^128 - 1) << 128 = type(uint256).max - (2^128 - 1)
        assertEq(m, type(uint256).max - ((uint256(1) << 128) - 1));
        // Encode max value
        uint256 encoded = harness.encode(q, m);
        assertEq(encoded, (uint256(1) << 128) - 1);
        // Round-trip
        assertEq(harness.decode(q, encoded), m);
    }

    // -------------------------------------------------------------------------
    // Boundary: encodedBitWidth == 255 (near-max encoded width)
    // -------------------------------------------------------------------------

    function test_encodedBitWidth_255() public view {
        // discardedBitWidth=1, encodedBitWidth=255: max = (2^255 - 1) << 1
        Quant q = harness.create(1, 255);
        uint256 m = harness.max(q);
        assertEq(m, ((uint256(1) << 255) - 1) << 1);
        assertTrue(harness.fits(q, m));
        assertFalse(harness.fits(q, type(uint256).max)); // type(uint256).max > m, does not fit
    }

    // -------------------------------------------------------------------------
    // Boundary: explicit zero encode/decode
    // -------------------------------------------------------------------------

    function test_encode_decode_zero() public view {
        Quant q = harness.create(8, 8);
        assertEq(harness.encode(q, 0), 0);
        assertEq(harness.decode(q, 0), 0);
        assertEq(harness.decodeMax(q, 0), 255); // fills low bits with 1s
        assertEq(harness.remainder(q, 0), 0);
        assertTrue(harness.isAligned(q, 0));
        assertTrue(harness.fits(q, 0));
    }

    // -------------------------------------------------------------------------
    // Boundary: discardedBitWidth == 0, encodedBitWidth == 1 (minimal config)
    // -------------------------------------------------------------------------

    function test_minimal_config() public view {
        // Smallest valid config: 1-bit encoded, no shift
        Quant q = harness.create(0, 1);
        assertEq(harness.max(q), 1);
        assertEq(harness.encode(q, 0), 0);
        assertEq(harness.encode(q, 1), 1);
    }

    function test_minimal_config_overflow_reverts() public {
        Quant q = harness.create(0, 1);
        // 2 should overflow (max is 1)
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, uint256(2), uint256(1)));
        harness.encode(q, 2);
    }

    // -------------------------------------------------------------------------
    // isValid: create-produced vs hand-wrapped
    // -------------------------------------------------------------------------

    function test_isValid_handWrapped_invalid() public view {
        // encodedBitWidth=0 (invalid: rejected by create)
        assertFalse(harness.isValid(Quant.wrap(0)));
        // discardedBitWidth=255, encodedBitWidth=255: sum=510 > 256
        assertFalse(harness.isValid(Quant.wrap(uint16(0xFF00 | 0xFF))));
    }

    // -------------------------------------------------------------------------
    // decode: checked revert on oversized encoded
    // -------------------------------------------------------------------------

    function test_decode_oversized_reverts() public {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        // encodedBitWidth=8, so max encoded = 255; 256 is out of range
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, uint256(256), uint256(255)));
        harness.decode(q, 256);
    }

    function test_decodeMax_oversized_reverts() public {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, uint256(256), uint256(255)));
        harness.decodeMax(q, 256);
    }

    // -------------------------------------------------------------------------
    // ceil: overflow revert
    // -------------------------------------------------------------------------

    function test_ceil_overflow_reverts() public {
        Quant q = harness.create(DISCARDED_8, ENCODED_8);
        // type(uint256).max is not aligned to 256; rounding up overflows
        vm.expectRevert(abi.encodeWithSelector(CeilOverflow.selector, type(uint256).max));
        harness.ceil(q, type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------------

    function testFuzz_floor_is_aligned(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        uint256 floored = harness.floor(q, value);
        assertTrue(harness.isAligned(q, floored));
    }

    function testFuzz_lower_bound_round_trip(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        // Use bound instead of assume: schemes with small max reject most random uint256 values.
        value = bound(value, 0, harness.max(q));
        uint256 decoded = harness.decode(q, harness.encode(q, value));
        assertLe(decoded, value);
    }

    function testFuzz_decodeMax_ge_decode(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 encoded) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        // Bound to valid encoded range so the test exercises the documented domain.
        encoded = bound(encoded, 0, (uint256(1) << harness.encodedBitWidth(q)) - 1);
        assertGe(harness.decodeMax(q, encoded), harness.decode(q, encoded));
    }

    function testFuzz_remainder_lt_stepSize(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        assertLt(harness.remainder(q, value), harness.stepSize(q));
    }

    function testFuzz_isAligned_equivalence(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        assertEq(harness.isAligned(q, value), harness.remainder(q, value) == 0);
    }

    function testFuzz_fits_equivalence(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        assertEq(harness.fits(q, value), value <= harness.max(q));
    }

    function testFuzz_ceil_ge_value(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 value) public {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        uint256 s = uint256(discardedBitWidth_);
        if (s > 0) {
            uint256 mask = (uint256(1) << s) - 1;
            if (value >= type(uint256).max - mask && value & mask != 0) {
                // Overflow region: ceil should revert
                vm.expectRevert(abi.encodeWithSelector(CeilOverflow.selector, value));
                harness.ceil(q, value);
                return;
            }
        }
        assertGe(harness.ceil(q, value), value);
    }

    function testFuzz_encode_monotonicity(uint8 discardedBitWidth_, uint8 encodedBitWidth_, uint256 v1, uint256 v2) public view {
        vm.assume(encodedBitWidth_ > 0 && uint256(discardedBitWidth_) + uint256(encodedBitWidth_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(discardedBitWidth_), uint256(encodedBitWidth_));
        uint256 m = harness.max(q);
        // Use bound instead of assume: schemes with small max reject most random uint256 values.
        v1 = bound(v1, 0, m);
        v2 = bound(v2, 0, m);
        if (v1 > v2) (v1, v2) = (v2, v1);
        assertLe(harness.encode(q, v1), harness.encode(q, v2));
    }
}
