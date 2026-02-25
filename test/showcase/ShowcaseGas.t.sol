// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    QuantizedERC20StateShowcase,
    QuantizedExtremePackingShowcase,
    RawERC20StateShowcase,
    RawExtremePackingShowcase
} from "src/showcase/ShowcaseSolidityFixtures.sol";
import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

interface IRawERC20StateShowcaseVyper {
    function set_state_raw(uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor)
        external;
}

interface IQuantizedERC20StateShowcaseVyper {
    function set_state_floor(
        uint256 _totalSupply,
        uint256 _treasuryBalance,
        uint256 _feeAccumulator,
        uint256 _nonceCursor
    ) external;
    function set_state_strict(
        uint256 _totalSupply,
        uint256 _treasuryBalance,
        uint256 _feeAccumulator,
        uint256 _nonceCursor
    ) external;
    function encoded_state()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor);
    function decode_state_floor()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor);
    function decode_state_ceil()
        external
        view
        returns (uint256 _totalSupply, uint256 _treasuryBalance, uint256 _feeAccumulator, uint256 _nonceCursor);
}

interface IRawExtremePackingShowcaseVyper {
    function set_extreme_raw(uint256[12] calldata values) external;
}

interface IQuantizedExtremePackingShowcaseVyper {
    function set_extreme_floor(uint256[12] calldata values) external;
    function set_extreme_strict(uint256[12] calldata values) external;
    function encoded_extreme() external view returns (uint256[12] memory values);
    function decode_extreme_floor() external view returns (uint256[12] memory values);
    function decode_extreme_ceil() external view returns (uint256[12] memory values);
}

contract ShowcaseGasTest is Test {
    uint256 internal constant REAL_SHIFT = 16;
    uint256 internal constant REAL_WIDTH = 40;
    uint256 internal constant REAL_LANE_MAX = (uint256(1) << REAL_WIDTH) - 1;

    uint256 internal constant EXT_SHIFT = 8;
    uint256 internal constant EXT_WIDTH = 20;
    uint256 internal constant EXT_LANES = 12;
    uint256 internal constant EXT_LANE_MAX = (uint256(1) << EXT_WIDTH) - 1;

    uint256 internal constant MIN_REAL_SAVINGS_BPS = 5_000; // >=50%
    uint256 internal constant MIN_EXTREME_SAVINGS_BPS = 8_000; // >=80%

    uint256 internal constant REAL_TOTAL_SUPPLY_STRICT = uint256(1_000_000_000) << REAL_SHIFT;
    uint256 internal constant REAL_TREASURY_STRICT = uint256(120_000_000) << REAL_SHIFT;
    uint256 internal constant REAL_FEES_STRICT = uint256(8_500_000) << REAL_SHIFT;
    uint256 internal constant REAL_NONCE_STRICT = uint256(450_000) << REAL_SHIFT;

    uint256 internal constant REAL_TOTAL_SUPPLY_FLOOR = REAL_TOTAL_SUPPLY_STRICT + 321;
    uint256 internal constant REAL_TREASURY_FLOOR = REAL_TREASURY_STRICT + 1_024;
    uint256 internal constant REAL_FEES_FLOOR = REAL_FEES_STRICT + 7;
    uint256 internal constant REAL_NONCE_FLOOR = REAL_NONCE_STRICT + 65_535;

    uint256 internal constant EXT_E0 = 1_000_000;
    uint256 internal constant EXT_E1 = 970_000;
    uint256 internal constant EXT_E2 = 940_000;
    uint256 internal constant EXT_E3 = 910_000;
    uint256 internal constant EXT_E4 = 880_000;
    uint256 internal constant EXT_E5 = 850_000;
    uint256 internal constant EXT_E6 = 820_000;
    uint256 internal constant EXT_E7 = 790_000;
    uint256 internal constant EXT_E8 = 760_000;
    uint256 internal constant EXT_E9 = 730_000;
    uint256 internal constant EXT_E10 = 700_000;
    uint256 internal constant EXT_E11 = 670_000;

    uint256 internal constant EXT_R0 = 13;
    uint256 internal constant EXT_R1 = 27;
    uint256 internal constant EXT_R2 = 55;
    uint256 internal constant EXT_R3 = 89;
    uint256 internal constant EXT_R4 = 144;
    uint256 internal constant EXT_R5 = 233;
    uint256 internal constant EXT_R6 = 7;
    uint256 internal constant EXT_R7 = 31;
    uint256 internal constant EXT_R8 = 63;
    uint256 internal constant EXT_R9 = 95;
    uint256 internal constant EXT_R10 = 127;
    uint256 internal constant EXT_R11 = 191;

    function test_real_life_floor_parity_and_bounds() public {
        QuantizedERC20StateShowcase solidityQuantized = new QuantizedERC20StateShowcase();
        IQuantizedERC20StateShowcaseVyper vyperQuantized =
            IQuantizedERC20StateShowcaseVyper(deployCode("QuantizedERC20StateShowcase.vy"));

        solidityQuantized.setStateFloor(
            REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR
        );
        vyperQuantized.set_state_floor(
            REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR
        );

        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.encodedState.selector,
            address(vyperQuantized),
            vyperQuantized.encoded_state.selector
        );
        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeStateFloor.selector,
            address(vyperQuantized),
            vyperQuantized.decode_state_floor.selector
        );
        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeStateCeil.selector,
            address(vyperQuantized),
            vyperQuantized.decode_state_ceil.selector
        );

        (uint256 l0, uint256 l1, uint256 l2, uint256 l3) = solidityQuantized.decodeStateFloor();
        (uint256 u0, uint256 u1, uint256 u2, uint256 u3) = solidityQuantized.decodeStateCeil();

        assertLe(l0, REAL_TOTAL_SUPPLY_FLOOR);
        assertLe(l1, REAL_TREASURY_FLOOR);
        assertLe(l2, REAL_FEES_FLOOR);
        assertLe(l3, REAL_NONCE_FLOOR);

        assertGe(u0, REAL_TOTAL_SUPPLY_FLOOR);
        assertGe(u1, REAL_TREASURY_FLOOR);
        assertGe(u2, REAL_FEES_FLOOR);
        assertGe(u3, REAL_NONCE_FLOOR);
    }

    function test_real_life_strict_round_trip_and_revert() public {
        QuantizedERC20StateShowcase solidityQuantized = new QuantizedERC20StateShowcase();
        IQuantizedERC20StateShowcaseVyper vyperQuantized =
            IQuantizedERC20StateShowcaseVyper(deployCode("QuantizedERC20StateShowcase.vy"));

        solidityQuantized.setStateStrict(
            REAL_TOTAL_SUPPLY_STRICT, REAL_TREASURY_STRICT, REAL_FEES_STRICT, REAL_NONCE_STRICT
        );
        vyperQuantized.set_state_strict(
            REAL_TOTAL_SUPPLY_STRICT, REAL_TREASURY_STRICT, REAL_FEES_STRICT, REAL_NONCE_STRICT
        );

        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeStateFloor.selector,
            address(vyperQuantized),
            vyperQuantized.decode_state_floor.selector
        );

        (uint256 s0, uint256 s1, uint256 s2, uint256 s3) = solidityQuantized.decodeStateFloor();
        assertEq(s0, REAL_TOTAL_SUPPLY_STRICT);
        assertEq(s1, REAL_TREASURY_STRICT);
        assertEq(s2, REAL_FEES_STRICT);
        assertEq(s3, REAL_NONCE_STRICT);

        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__InexactInput.selector,
                REAL_TOTAL_SUPPLY_FLOOR,
                REAL_SHIFT,
                uint256(321)
            )
        );
        solidityQuantized.setStateStrict(
            REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_STRICT, REAL_FEES_STRICT, REAL_NONCE_STRICT
        );

        bytes memory callData = abi.encodeWithSelector(
            vyperQuantized.set_state_strict.selector,
            REAL_TOTAL_SUPPLY_FLOOR,
            REAL_TREASURY_STRICT,
            REAL_FEES_STRICT,
            REAL_NONCE_STRICT
        );
        (bool success,) = address(vyperQuantized).call(callData);
        assertFalse(success);
    }

    function test_extreme_floor_parity_and_bounds() public {
        QuantizedExtremePackingShowcase solidityQuantized = new QuantizedExtremePackingShowcase();
        IQuantizedExtremePackingShowcaseVyper vyperQuantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));

        uint256[12] memory values = _extremeFloorValues();

        solidityQuantized.setExtremeFloor(values);
        vyperQuantized.set_extreme_floor(values);

        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.encodedExtreme.selector,
            address(vyperQuantized),
            vyperQuantized.encoded_extreme.selector
        );
        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeExtremeFloor.selector,
            address(vyperQuantized),
            vyperQuantized.decode_extreme_floor.selector
        );
        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeExtremeCeil.selector,
            address(vyperQuantized),
            vyperQuantized.decode_extreme_ceil.selector
        );

        uint256[12] memory lower = solidityQuantized.decodeExtremeFloor();
        uint256[12] memory upper = solidityQuantized.decodeExtremeCeil();
        for (uint256 i; i < EXT_LANES; ++i) {
            assertLe(lower[i], values[i]);
            assertGe(upper[i], values[i]);
        }
    }

    function test_extreme_strict_round_trip_and_revert() public {
        QuantizedExtremePackingShowcase solidityQuantized = new QuantizedExtremePackingShowcase();
        IQuantizedExtremePackingShowcaseVyper vyperQuantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));

        uint256[12] memory strictValues = _extremeStrictValues();
        uint256[12] memory floorValues = _extremeFloorValues();

        solidityQuantized.setExtremeStrict(strictValues);
        vyperQuantized.set_extreme_strict(strictValues);

        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.decodeExtremeFloor.selector,
            address(vyperQuantized),
            vyperQuantized.decode_extreme_floor.selector
        );

        uint256[12] memory restored = solidityQuantized.decodeExtremeFloor();
        for (uint256 i; i < EXT_LANES; ++i) {
            assertEq(restored[i], strictValues[i]);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__InexactInput.selector, floorValues[0], EXT_SHIFT, EXT_R0
            )
        );
        solidityQuantized.setExtremeStrict(floorValues);

        bytes memory callData = abi.encodeWithSelector(vyperQuantized.set_extreme_strict.selector, floorValues);
        (bool success,) = address(vyperQuantized).call(callData);
        assertFalse(success);
    }

    function test_gas_real_life_solidity_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureSolidityRealRaw();
        uint256 floorGas = _measureSolidityRealQuantFloor();
        uint256 strictGas = _measureSolidityRealQuantStrict();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_REAL_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_REAL_SAVINGS_BPS);
    }

    function test_gas_real_life_vyper_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureVyperRealRaw();
        uint256 floorGas = _measureVyperRealQuantFloor();
        uint256 strictGas = _measureVyperRealQuantStrict();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_REAL_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_REAL_SAVINGS_BPS);
    }

    function test_gas_extreme_solidity_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureSolidityExtremeRaw();
        uint256 floorGas = _measureSolidityExtremeQuantFloor();
        uint256 strictGas = _measureSolidityExtremeQuantStrict();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_EXTREME_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_EXTREME_SAVINGS_BPS);
    }

    function test_gas_extreme_vyper_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureVyperExtremeRaw();
        uint256 floorGas = _measureVyperExtremeQuantFloor();
        uint256 strictGas = _measureVyperExtremeQuantStrict();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_EXTREME_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_EXTREME_SAVINGS_BPS);
    }

    function test_showcase_inputs_fit_lanes() public pure {
        assertLe(REAL_TOTAL_SUPPLY_FLOOR >> REAL_SHIFT, REAL_LANE_MAX);
        assertLe(REAL_TREASURY_FLOOR >> REAL_SHIFT, REAL_LANE_MAX);
        assertLe(REAL_FEES_FLOOR >> REAL_SHIFT, REAL_LANE_MAX);
        assertLe(REAL_NONCE_FLOOR >> REAL_SHIFT, REAL_LANE_MAX);

        uint256[12] memory strictValues = _extremeStrictValues();
        uint256[12] memory floorValues = _extremeFloorValues();
        for (uint256 i; i < EXT_LANES; ++i) {
            assertLe(strictValues[i] >> EXT_SHIFT, EXT_LANE_MAX);
            assertLe(floorValues[i] >> EXT_SHIFT, EXT_LANE_MAX);
        }
    }

    function _assertStaticcallEqual(address lhs, bytes4 lhsSelector, address rhs, bytes4 rhsSelector) internal view {
        (bool lhsOk, bytes memory lhsData) = lhs.staticcall(abi.encodeWithSelector(lhsSelector));
        (bool rhsOk, bytes memory rhsData) = rhs.staticcall(abi.encodeWithSelector(rhsSelector));
        assertTrue(lhsOk);
        assertTrue(rhsOk);
        assertEq(keccak256(lhsData), keccak256(rhsData));
    }

    function _extremeStrictValues() internal pure returns (uint256[12] memory values) {
        values[0] = EXT_E0 << EXT_SHIFT;
        values[1] = EXT_E1 << EXT_SHIFT;
        values[2] = EXT_E2 << EXT_SHIFT;
        values[3] = EXT_E3 << EXT_SHIFT;
        values[4] = EXT_E4 << EXT_SHIFT;
        values[5] = EXT_E5 << EXT_SHIFT;
        values[6] = EXT_E6 << EXT_SHIFT;
        values[7] = EXT_E7 << EXT_SHIFT;
        values[8] = EXT_E8 << EXT_SHIFT;
        values[9] = EXT_E9 << EXT_SHIFT;
        values[10] = EXT_E10 << EXT_SHIFT;
        values[11] = EXT_E11 << EXT_SHIFT;
    }

    function _extremeFloorValues() internal pure returns (uint256[12] memory values) {
        values[0] = (EXT_E0 << EXT_SHIFT) + EXT_R0;
        values[1] = (EXT_E1 << EXT_SHIFT) + EXT_R1;
        values[2] = (EXT_E2 << EXT_SHIFT) + EXT_R2;
        values[3] = (EXT_E3 << EXT_SHIFT) + EXT_R3;
        values[4] = (EXT_E4 << EXT_SHIFT) + EXT_R4;
        values[5] = (EXT_E5 << EXT_SHIFT) + EXT_R5;
        values[6] = (EXT_E6 << EXT_SHIFT) + EXT_R6;
        values[7] = (EXT_E7 << EXT_SHIFT) + EXT_R7;
        values[8] = (EXT_E8 << EXT_SHIFT) + EXT_R8;
        values[9] = (EXT_E9 << EXT_SHIFT) + EXT_R9;
        values[10] = (EXT_E10 << EXT_SHIFT) + EXT_R10;
        values[11] = (EXT_E11 << EXT_SHIFT) + EXT_R11;
    }

    function _savingsBps(uint256 rawGas, uint256 quantizedGas) internal pure returns (uint256) {
        return ((rawGas - quantizedGas) * 10_000) / rawGas;
    }

    function _measureSolidityRealRaw() internal returns (uint256) {
        RawERC20StateShowcase raw = new RawERC20StateShowcase();
        raw.setStateRaw(REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantFloor() internal returns (uint256) {
        QuantizedERC20StateShowcase quantized = new QuantizedERC20StateShowcase();
        quantized.setStateFloor(REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantStrict() internal returns (uint256) {
        QuantizedERC20StateShowcase quantized = new QuantizedERC20StateShowcase();
        quantized.setStateStrict(REAL_TOTAL_SUPPLY_STRICT, REAL_TREASURY_STRICT, REAL_FEES_STRICT, REAL_NONCE_STRICT);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealRaw() internal returns (uint256) {
        IRawERC20StateShowcaseVyper raw = IRawERC20StateShowcaseVyper(deployCode("RawERC20StateShowcase.vy"));
        raw.set_state_raw(REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantFloor() internal returns (uint256) {
        IQuantizedERC20StateShowcaseVyper quantized =
            IQuantizedERC20StateShowcaseVyper(deployCode("QuantizedERC20StateShowcase.vy"));
        quantized.set_state_floor(REAL_TOTAL_SUPPLY_FLOOR, REAL_TREASURY_FLOOR, REAL_FEES_FLOOR, REAL_NONCE_FLOOR);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantStrict() internal returns (uint256) {
        IQuantizedERC20StateShowcaseVyper quantized =
            IQuantizedERC20StateShowcaseVyper(deployCode("QuantizedERC20StateShowcase.vy"));
        quantized.set_state_strict(REAL_TOTAL_SUPPLY_STRICT, REAL_TREASURY_STRICT, REAL_FEES_STRICT, REAL_NONCE_STRICT);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeRaw() internal returns (uint256) {
        RawExtremePackingShowcase raw = new RawExtremePackingShowcase();
        uint256[12] memory values = _extremeFloorValues();
        raw.setExtremeRaw(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantFloor() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory values = _extremeFloorValues();
        quantized.setExtremeFloor(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantStrict() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory values = _extremeStrictValues();
        quantized.setExtremeStrict(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeRaw() internal returns (uint256) {
        IRawExtremePackingShowcaseVyper raw = IRawExtremePackingShowcaseVyper(deployCode("RawExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeFloorValues();
        raw.set_extreme_raw(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantFloor() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeFloorValues();
        quantized.set_extreme_floor(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantStrict() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeStrictValues();
        quantized.set_extreme_strict(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }
}
