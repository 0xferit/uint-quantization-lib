// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Quant, UintQuantizationLib, Overflow, NotAligned, BadConfig} from "src/UintQuantizationLib.sol";

/// @notice Thin harness that exposes library functions via `using-for` so tests call them on
///         `Quant` values rather than through the library name directly.
contract QuantHarness {
    function create(uint256 shift_, uint256 targetBits_) external pure returns (Quant) {
        return UintQuantizationLib.create(shift_, targetBits_);
    }

    function shift(Quant q) external pure returns (uint256) {
        return q.shift();
    }

    function targetBits(Quant q) external pure returns (uint256) {
        return q.targetBits();
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

    function remainder(Quant q, uint256 value) external pure returns (uint256) {
        return q.remainder(value);
    }

    function isLossless(Quant q, uint256 value) external pure returns (bool) {
        return q.isLossless(value);
    }

    function fits(Quant q, uint256 value) external pure returns (bool) {
        return q.fits(value);
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

    // shift=8, targetBits=8: stepSize=256, max=65280
    uint256 private constant SHIFT_8 = 8;
    uint256 private constant BITS_8 = 8;

    function setUp() public {
        harness = new QuantHarness();
    }

    // -------------------------------------------------------------------------
    // create: bad config reverts
    // -------------------------------------------------------------------------

    function test_create_shiftTooLarge_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(256), uint256(8)));
        harness.create(256, 8);
    }

    function test_create_targetBitsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(8), uint256(0)));
        harness.create(8, 0);
    }

    function test_create_targetBits256_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(8), uint256(256)));
        harness.create(8, 256);
    }

    function test_create_shiftPlusTargetBitsExceeds256_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(BadConfig.selector, uint256(200), uint256(100)));
        harness.create(200, 100);
    }

    // -------------------------------------------------------------------------
    // encode: overflow revert
    // -------------------------------------------------------------------------

    function test_encode_overflow_reverts() public {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 m = harness.max(q); // 65280
        uint256 value = m + 1; // 65281
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, value, m));
        harness.encode(q, value);
    }

    // -------------------------------------------------------------------------
    // encode (precise=true): overflow and alignment reverts
    // -------------------------------------------------------------------------

    function test_encodePrecise_overflow_reverts() public {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 m = harness.max(q);
        uint256 value = m + 1;
        vm.expectRevert(abi.encodeWithSelector(Overflow.selector, value, m));
        harness.encode(q, value, true);
    }

    function test_encodePrecise_notAligned_reverts() public {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 step = harness.stepSize(q); // 256
        uint256 value = step + 1; // 257, not aligned
        vm.expectRevert(abi.encodeWithSelector(NotAligned.selector, value, step));
        harness.encode(q, value, true);
    }

    function test_encodePrecise_aligned_succeeds() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 step = harness.stepSize(q); // 256
        // 256 is aligned: encode(256, true) == 1
        assertEq(harness.encode(q, step, true), 1);
    }

    // -------------------------------------------------------------------------
    // floor: concrete
    // -------------------------------------------------------------------------

    function test_floor_concrete() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        // 511 = 0x1FF; floor clears low 8 bits → 256
        uint256 result = harness.floor(q, 511);
        assertEq(result, 256);
        assertTrue(harness.isLossless(q, result));
    }

    // -------------------------------------------------------------------------
    // ceil: concrete (non-aligned and aligned)
    // -------------------------------------------------------------------------

    function test_ceil_nonAligned_concrete() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        // 257 is not aligned to 256; next step is 512
        uint256 result = harness.ceil(q, 257);
        assertEq(result, 512);
        assertGe(result, uint256(257));
        assertTrue(harness.isLossless(q, result));
    }

    function test_ceil_aligned_concrete() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        // 256 is already aligned; ceil returns it unchanged
        uint256 result = harness.ceil(q, 256);
        assertEq(result, 256);
    }

    // -------------------------------------------------------------------------
    // decodeMax: concrete
    // -------------------------------------------------------------------------

    function test_decodeMax_concrete() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        // decodeMax(3) = (3 << 8) | 255 = 768 | 255 = 1023
        uint256 result = harness.decodeMax(q, 3);
        assertEq(result, 1023);
        assertGe(result, harness.decode(q, 3));
    }

    // -------------------------------------------------------------------------
    // fits: sanity
    // -------------------------------------------------------------------------

    function test_fits_true() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 m = harness.max(q);
        assertTrue(harness.fits(q, m));
        assertTrue(harness.fits(q, 0));
    }

    function test_fits_false() public view {
        Quant q = harness.create(SHIFT_8, BITS_8);
        uint256 m = harness.max(q);
        assertFalse(harness.fits(q, m + 1));
    }

    // -------------------------------------------------------------------------
    // Boundary: shift == 0 (identity / no compression)
    // -------------------------------------------------------------------------

    function test_shift_zero_identity() public view {
        // shift=0, targetBits=8: stepSize=1, max=255, encode is identity
        Quant q = harness.create(0, 8);
        assertEq(harness.stepSize(q), 1);
        assertEq(harness.max(q), 255);
        assertEq(harness.encode(q, 200), 200);
        assertEq(harness.decode(q, 200), 200);
        assertTrue(harness.isLossless(q, 200));
        // ceil and floor are identity when shift=0
        assertEq(harness.floor(q, 137), 137);
        assertEq(harness.ceil(q, 137), 137);
    }

    // -------------------------------------------------------------------------
    // Boundary: shift + targetBits == 256 (full uint256 range)
    // -------------------------------------------------------------------------

    function test_full_uint256_range() public view {
        // shift=128, targetBits=128: uses the full 256-bit space
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
    // Boundary: targetBits == 255 (near-max encoded width)
    // -------------------------------------------------------------------------

    function test_targetBits_255() public view {
        // shift=1, targetBits=255: max = (2^255 - 1) << 1
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
        assertTrue(harness.isLossless(q, 0));
        assertTrue(harness.fits(q, 0));
    }

    // -------------------------------------------------------------------------
    // Boundary: shift == 0, targetBits == 1 (minimal config)
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
    // Fuzz tests
    // -------------------------------------------------------------------------

    function testFuzz_floor_is_lossless(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        uint256 floored = harness.floor(q, value);
        assertTrue(harness.isLossless(q, floored));
    }

    function testFuzz_lower_bound_round_trip(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        // Use bound instead of assume: schemes with small max reject most random uint256 values.
        value = bound(value, 0, harness.max(q));
        uint256 decoded = harness.decode(q, harness.encode(q, value));
        assertLe(decoded, value);
    }

    function testFuzz_decodeMax_ge_decode(uint8 shift_, uint8 targetBits_, uint256 encoded) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        assertGe(harness.decodeMax(q, encoded), harness.decode(q, encoded));
    }

    function testFuzz_remainder_lt_stepSize(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        assertLt(harness.remainder(q, value), harness.stepSize(q));
    }

    function testFuzz_isLossless_equivalence(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        assertEq(harness.isLossless(q, value), harness.remainder(q, value) == 0);
    }

    function testFuzz_fits_equivalence(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        assertEq(harness.fits(q, value), value <= harness.max(q));
    }

    function testFuzz_ceil_ge_value(uint8 shift_, uint8 targetBits_, uint256 value) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        uint256 s = uint256(shift_);
        if (s > 0) {
            uint256 mask = (uint256(1) << s) - 1;
            // Exclude values where (value | mask) + 1 would overflow uint256
            vm.assume(value < type(uint256).max - mask);
        }
        assertGe(harness.ceil(q, value), value);
    }

    function testFuzz_encode_monotonicity(uint8 shift_, uint8 targetBits_, uint256 v1, uint256 v2) public view {
        vm.assume(targetBits_ > 0 && uint256(shift_) + uint256(targetBits_) <= 256);
        Quant q = UintQuantizationLib.create(uint256(shift_), uint256(targetBits_));
        uint256 m = harness.max(q);
        // Use bound instead of assume: schemes with small max reject most random uint256 values.
        v1 = bound(v1, 0, m);
        v2 = bound(v2, 0, m);
        if (v1 > v2) (v1, v2) = (v2, v1);
        assertLe(harness.encode(q, v1), harness.encode(q, v2));
    }
}
