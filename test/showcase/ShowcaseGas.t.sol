// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    QuantizedUintPairStorageShowcase,
    RawUintPairStorageShowcase
} from "src/showcase/ShowcaseSolidityFixtures.sol";
import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

interface IRawUintPairStorageShowcaseVyper {
    function set_pair(uint256 a, uint256 b) external;
}

interface IQuantizedUintPairStorageShowcaseVyper {
    function set_pair_floor(uint256 a, uint256 b) external;
    function set_pair_strict(uint256 a, uint256 b) external;
    function encoded_pair() external view returns (uint256 encodedA, uint256 encodedB);
    function decode_floor() external view returns (uint256 lowerA, uint256 lowerB);
    function decode_ceil() external view returns (uint256 upperA, uint256 upperB);
}

contract ShowcaseGasTest is Test {
    uint256 internal constant SHIFT = 40;
    uint256 internal constant WIDTH = 56;
    uint256 internal constant LANE_MAX = (uint256(1) << WIDTH) - 1;

    uint256 internal constant FLOOR_A = (uint256(12_345) << SHIFT) + 321;
    uint256 internal constant FLOOR_B = (uint256(67_890) << SHIFT) + 987;

    uint256 internal constant STRICT_A = uint256(12_345) << SHIFT;
    uint256 internal constant STRICT_B = uint256(67_890) << SHIFT;

    uint256 internal constant ZERO_TO_NONZERO_MIN_SAVINGS = 5_000;

    function test_showcase_solidity_floor_bounds() public {
        QuantizedUintPairStorageShowcase quantized = new QuantizedUintPairStorageShowcase();
        quantized.setPairFloor(FLOOR_A, FLOOR_B);

        (uint256 lowerA, uint256 lowerB) = quantized.decodeFloor();
        (uint256 upperA, uint256 upperB) = quantized.decodeCeil();

        assertLe(lowerA, FLOOR_A);
        assertLe(lowerB, FLOOR_B);
        assertGe(upperA, FLOOR_A);
        assertGe(upperB, FLOOR_B);
    }

    function test_showcase_solidity_strict_round_trip() public {
        QuantizedUintPairStorageShowcase quantized = new QuantizedUintPairStorageShowcase();
        quantized.setPairStrict(STRICT_A, STRICT_B);

        (uint256 lowerA, uint256 lowerB) = quantized.decodeFloor();
        assertEq(lowerA, STRICT_A);
        assertEq(lowerB, STRICT_B);
    }

    function test_showcase_solidity_strict_reverts_on_inexact() public {
        QuantizedUintPairStorageShowcase quantized = new QuantizedUintPairStorageShowcase();
        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__InexactInput.selector,
                FLOOR_A,
                SHIFT,
                uint256(321)
            )
        );
        quantized.setPairStrict(FLOOR_A, STRICT_B);
    }

    function test_showcase_vyper_floor_bounds() public {
        IQuantizedUintPairStorageShowcaseVyper quantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));

        quantized.set_pair_floor(FLOOR_A, FLOOR_B);

        (uint256 lowerA, uint256 lowerB) = quantized.decode_floor();
        (uint256 upperA, uint256 upperB) = quantized.decode_ceil();

        assertLe(lowerA, FLOOR_A);
        assertLe(lowerB, FLOOR_B);
        assertGe(upperA, FLOOR_A);
        assertGe(upperB, FLOOR_B);
    }

    function test_showcase_vyper_strict_round_trip() public {
        IQuantizedUintPairStorageShowcaseVyper quantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));

        quantized.set_pair_strict(STRICT_A, STRICT_B);
        (uint256 lowerA, uint256 lowerB) = quantized.decode_floor();

        assertEq(lowerA, STRICT_A);
        assertEq(lowerB, STRICT_B);
    }

    function test_showcase_vyper_strict_reverts_on_inexact() public {
        IQuantizedUintPairStorageShowcaseVyper quantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));

        bytes memory callData = abi.encodeWithSelector(quantized.set_pair_strict.selector, FLOOR_A, STRICT_B);
        (bool success,) = address(quantized).call(callData);
        assertFalse(success);
    }

    function test_showcase_solidity_vyper_parity_for_floor_decode() public {
        QuantizedUintPairStorageShowcase solidityQuantized = new QuantizedUintPairStorageShowcase();
        IQuantizedUintPairStorageShowcaseVyper vyperQuantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));

        solidityQuantized.setPairFloor(FLOOR_A, FLOOR_B);
        vyperQuantized.set_pair_floor(FLOOR_A, FLOOR_B);

        (uint256 sEncodedA, uint256 sEncodedB) = solidityQuantized.encodedPair();
        (uint256 vEncodedA, uint256 vEncodedB) = vyperQuantized.encoded_pair();
        assertEq(sEncodedA, vEncodedA);
        assertEq(sEncodedB, vEncodedB);

        (uint256 sLowerA, uint256 sLowerB) = solidityQuantized.decodeFloor();
        (uint256 vLowerA, uint256 vLowerB) = vyperQuantized.decode_floor();
        assertEq(sLowerA, vLowerA);
        assertEq(sLowerB, vLowerB);

        (uint256 sUpperA, uint256 sUpperB) = solidityQuantized.decodeCeil();
        (uint256 vUpperA, uint256 vUpperB) = vyperQuantized.decode_ceil();
        assertEq(sUpperA, vUpperA);
        assertEq(sUpperB, vUpperB);
    }

    function test_gas_solidity_zero_to_nonzero_quantized_beats_raw() public {
        uint256 rawGas = _measureSolidityRawZeroToNonzero();
        uint256 floorGas = _measureSolidityQuantizedFloorZeroToNonzero();
        uint256 strictGas = _measureSolidityQuantizedStrictZeroToNonzero();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(rawGas - floorGas, ZERO_TO_NONZERO_MIN_SAVINGS);
        assertGe(rawGas - strictGas, ZERO_TO_NONZERO_MIN_SAVINGS);
    }

    function test_gas_vyper_zero_to_nonzero_quantized_beats_raw() public {
        uint256 rawGas = _measureVyperRawZeroToNonzero();
        uint256 floorGas = _measureVyperQuantizedFloorZeroToNonzero();
        uint256 strictGas = _measureVyperQuantizedStrictZeroToNonzero();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(rawGas - floorGas, ZERO_TO_NONZERO_MIN_SAVINGS);
        assertGe(rawGas - strictGas, ZERO_TO_NONZERO_MIN_SAVINGS);
    }

    function _measureSolidityRawZeroToNonzero() internal returns (uint256) {
        RawUintPairStorageShowcase raw = new RawUintPairStorageShowcase();
        raw.setPair(FLOOR_A, FLOOR_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityQuantizedFloorZeroToNonzero() internal returns (uint256) {
        QuantizedUintPairStorageShowcase quantized = new QuantizedUintPairStorageShowcase();
        quantized.setPairFloor(FLOOR_A, FLOOR_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityQuantizedStrictZeroToNonzero() internal returns (uint256) {
        QuantizedUintPairStorageShowcase quantized = new QuantizedUintPairStorageShowcase();
        quantized.setPairStrict(STRICT_A, STRICT_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRawZeroToNonzero() internal returns (uint256) {
        IRawUintPairStorageShowcaseVyper raw =
            IRawUintPairStorageShowcaseVyper(deployCode("RawUintPairStorageShowcase.vy"));
        raw.set_pair(FLOOR_A, FLOOR_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperQuantizedFloorZeroToNonzero() internal returns (uint256) {
        IQuantizedUintPairStorageShowcaseVyper quantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));
        quantized.set_pair_floor(FLOOR_A, FLOOR_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperQuantizedStrictZeroToNonzero() internal returns (uint256) {
        IQuantizedUintPairStorageShowcaseVyper quantized =
            IQuantizedUintPairStorageShowcaseVyper(deployCode("QuantizedUintPairStorageShowcase.vy"));
        quantized.set_pair_strict(STRICT_A, STRICT_B);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function test_showcase_inputs_fit_lane() public pure {
        assertLe(FLOOR_A >> SHIFT, LANE_MAX);
        assertLe(FLOOR_B >> SHIFT, LANE_MAX);
        assertLe(STRICT_A >> SHIFT, LANE_MAX);
        assertLe(STRICT_B >> SHIFT, LANE_MAX);
    }
}
