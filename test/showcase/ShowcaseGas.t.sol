// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    QuantizedETHStakingShowcase,
    QuantizedExtremePackingShowcase,
    RawETHStakingShowcase,
    RawExtremePackingShowcase
} from "src/showcase/ShowcaseSolidityFixtures.sol";
import {UintQuantizationLib} from "src/UintQuantizationLib.sol";

interface IRawETHStakingShowcaseVyper {
    function stake() external payable;
    function unstake() external;
}

interface IQuantizedETHStakingShowcaseVyper {
    function stake() external payable;
    function stake_exact() external payable;
    function unstake() external;
    function encoded_stake(address user)
        external
        view
        returns (uint96 amount, uint64 stakedAt, uint64 cooldownEndsAt, bool active);
    function get_stake(address user) external view returns (uint256);
    function max_deposit() external view returns (uint256);
    function stake_remainder(uint256 amount) external view returns (uint256);
    function is_stake_lossless(uint256 amount) external view returns (bool);
}

interface IRawExtremePackingShowcaseVyper {
    function set_extreme_raw(uint256[12] calldata values) external;
}

interface IQuantizedExtremePackingShowcaseVyper {
    function set_extreme_floor(uint256[12] calldata values) external;
    function set_extreme_strict(uint256[12] calldata values) external;
    function encoded_extreme() external view returns (uint256[12] memory values);
    function decode_extreme_floor() external view returns (uint256[12] memory values);
}

contract ShowcaseGasTest is Test {
    using UintQuantizationLib for uint256;

    uint256 internal constant REAL_SHIFT = 16;
    uint256 internal constant REAL_AMOUNT_BITS = 96;
    uint256 internal constant REAL_AMOUNT_MAX = (uint256(1) << REAL_AMOUNT_BITS) - 1;

    uint256 internal constant EXT_SHIFT = 8;
    uint256 internal constant EXT_WIDTH = 20;
    uint256 internal constant EXT_LANES = 12;
    uint256 internal constant EXT_LANE_MAX = (uint256(1) << EXT_WIDTH) - 1;

    uint256 internal constant MIN_REAL_SAVINGS_BPS = 3_200; // >=32%
    uint256 internal constant MIN_EXTREME_SAVINGS_BPS = 8_000; // >=80%

    uint256 internal constant REAL_STAKE_STRICT = uint256(2_500_000) << REAL_SHIFT;
    uint256 internal constant REAL_STAKE_STRICT_ALT = uint256(2_750_000) << REAL_SHIFT;
    uint256 internal constant REAL_STAKE_FLOOR = REAL_STAKE_STRICT + 321;

    uint256 internal constant FEE_INPUT = 123_456_789;
    uint256 internal constant FEE_SHIFT = 12;

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

    receive() external payable {}

    function setUp() public {
        vm.deal(address(this), 1_000_000 ether);
    }

    function test_real_life_floor_parity_bounds_and_helpers() public {
        QuantizedETHStakingShowcase solidityQuantized = new QuantizedETHStakingShowcase();
        IQuantizedETHStakingShowcaseVyper vyperQuantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));

        solidityQuantized.stake{value: REAL_STAKE_FLOOR}();
        vyperQuantized.stake{value: REAL_STAKE_FLOOR}();

        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.encodedStake.selector,
            address(vyperQuantized),
            vyperQuantized.encoded_stake.selector,
            abi.encode(address(this))
        );
        _assertStaticcallEqual(
            address(solidityQuantized),
            solidityQuantized.getStake.selector,
            address(vyperQuantized),
            vyperQuantized.get_stake.selector,
            abi.encode(address(this))
        );

        uint256 stake = solidityQuantized.getStake(address(this));
        assertLe(stake, REAL_STAKE_FLOOR);

        uint256 expectedMax = UintQuantizationLib.maxRepresentable(REAL_SHIFT, REAL_AMOUNT_BITS);
        assertEq(solidityQuantized.maxDeposit(), expectedMax);
        assertEq(vyperQuantized.max_deposit(), expectedMax);

        uint256 expectedRemainder = REAL_STAKE_FLOOR.remainder(REAL_SHIFT);
        assertEq(solidityQuantized.stakeRemainder(REAL_STAKE_FLOOR), expectedRemainder);
        assertEq(vyperQuantized.stake_remainder(REAL_STAKE_FLOOR), expectedRemainder);
        assertFalse(solidityQuantized.isStakeLossless(REAL_STAKE_FLOOR));
        assertFalse(vyperQuantized.is_stake_lossless(REAL_STAKE_FLOOR));
        assertTrue(solidityQuantized.isStakeLossless(REAL_STAKE_STRICT));
        assertTrue(vyperQuantized.is_stake_lossless(REAL_STAKE_STRICT));
    }

    function test_real_life_stake_exact_round_trip_and_revert_on_inexact() public {
        QuantizedETHStakingShowcase solidityQuantized = new QuantizedETHStakingShowcase();
        IQuantizedETHStakingShowcaseVyper vyperQuantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));

        solidityQuantized.stakeExact{value: REAL_STAKE_STRICT}();
        vyperQuantized.stake_exact{value: REAL_STAKE_STRICT}();

        assertEq(solidityQuantized.getStake(address(this)), REAL_STAKE_STRICT);
        assertEq(vyperQuantized.get_stake(address(this)), REAL_STAKE_STRICT);

        vm.expectRevert(
            abi.encodeWithSelector(
                UintQuantizationLib.UintQuantizationLib__InexactInput.selector,
                REAL_STAKE_FLOOR,
                REAL_SHIFT,
                uint256(321)
            )
        );
        solidityQuantized.stakeExact{value: REAL_STAKE_FLOOR}();

        bytes memory callData = abi.encodeWithSelector(vyperQuantized.stake_exact.selector);
        (bool success,) = address(vyperQuantized).call{value: REAL_STAKE_FLOOR}(callData);
        assertFalse(success);
    }

    function test_real_life_unstake_decodes_floor_value() public {
        QuantizedETHStakingShowcase solidityQuantized = new QuantizedETHStakingShowcase();
        IQuantizedETHStakingShowcaseVyper vyperQuantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));

        uint256 expectedPayout = REAL_STAKE_FLOOR.encode(REAL_SHIFT).decode(REAL_SHIFT);

        uint256 solBefore = address(this).balance;
        solidityQuantized.stake{value: REAL_STAKE_FLOOR}();
        uint256 solMid = address(this).balance;
        solidityQuantized.unstake();
        uint256 solAfter = address(this).balance;

        assertEq(solBefore - solMid, REAL_STAKE_FLOOR);
        assertEq(solAfter - solMid, expectedPayout);
        (, uint64 solStakedAt, uint64 solCooldownEndsAt, bool solActive) = solidityQuantized.encodedStake(address(this));
        assertEq(solStakedAt, 0);
        assertEq(solCooldownEndsAt, 0);
        assertFalse(solActive);

        uint256 vBefore = address(this).balance;
        vyperQuantized.stake{value: REAL_STAKE_FLOOR}();
        uint256 vMid = address(this).balance;
        vyperQuantized.unstake();
        uint256 vAfter = address(this).balance;

        assertEq(vBefore - vMid, REAL_STAKE_FLOOR);
        assertEq(vAfter - vMid, expectedPayout);
        (, uint64 vStakedAt, uint64 vCooldownEndsAt, bool vActive) = vyperQuantized.encoded_stake(address(this));
        assertEq(vStakedAt, 0);
        assertEq(vCooldownEndsAt, 0);
        assertFalse(vActive);
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

        uint256[12] memory lower = solidityQuantized.decodeExtremeFloor();
        for (uint256 i; i < EXT_LANES; ++i) {
            assertLe(lower[i], values[i]);
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
        uint256 rawGas = _measureSolidityRealRawStake();
        uint256 floorGas = _measureSolidityRealQuantFloorStake();
        uint256 strictGas = _measureSolidityRealQuantStrictStake();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_REAL_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_REAL_SAVINGS_BPS);
    }

    function test_gas_real_life_vyper_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureVyperRealRawStake();
        uint256 floorGas = _measureVyperRealQuantFloorStake();
        uint256 strictGas = _measureVyperRealQuantStrictStake();

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

    function test_gas_real_life_solidity_nonzero_to_nonzero_metrics() public {
        uint256 rawGas = _measureSolidityRealRawStakeWarm();
        uint256 floorGas = _measureSolidityRealQuantFloorStakeWarm();
        uint256 strictGas = _measureSolidityRealQuantStrictStakeWarm();

        emit log_named_uint("warm_real_life_solidity_raw", rawGas);
        emit log_named_uint("warm_real_life_solidity_quant_floor", floorGas);
        emit log_named_uint("warm_real_life_solidity_quant_strict", strictGas);

        assertGt(rawGas, 0);
        assertGt(floorGas, 0);
        assertGt(strictGas, 0);
        assertLt(rawGas, _measureSolidityRealRawStake());
        assertLt(floorGas, _measureSolidityRealQuantFloorStake());
        assertLt(strictGas, _measureSolidityRealQuantStrictStake());
    }

    function test_gas_real_life_vyper_nonzero_to_nonzero_metrics() public {
        uint256 rawGas = _measureVyperRealRawStakeWarm();
        uint256 floorGas = _measureVyperRealQuantFloorStakeWarm();
        uint256 strictGas = _measureVyperRealQuantStrictStakeWarm();

        emit log_named_uint("warm_real_life_vyper_raw", rawGas);
        emit log_named_uint("warm_real_life_vyper_quant_floor", floorGas);
        emit log_named_uint("warm_real_life_vyper_quant_strict", strictGas);

        assertGt(rawGas, 0);
        assertGt(floorGas, 0);
        assertGt(strictGas, 0);
        assertLt(rawGas, _measureVyperRealRawStake());
        assertLt(floorGas, _measureVyperRealQuantFloorStake());
        assertLt(strictGas, _measureVyperRealQuantStrictStake());
    }

    function test_gas_extreme_solidity_nonzero_to_nonzero_metrics() public {
        uint256 rawGas = _measureSolidityExtremeRawWarm();
        uint256 floorGas = _measureSolidityExtremeQuantFloorWarm();
        uint256 strictGas = _measureSolidityExtremeQuantStrictWarm();

        emit log_named_uint("warm_extreme_solidity_raw", rawGas);
        emit log_named_uint("warm_extreme_solidity_quant_floor", floorGas);
        emit log_named_uint("warm_extreme_solidity_quant_strict", strictGas);

        assertGt(rawGas, 0);
        assertGt(floorGas, 0);
        assertGt(strictGas, 0);
        assertLt(rawGas, _measureSolidityExtremeRaw());
        assertLt(floorGas, _measureSolidityExtremeQuantFloor());
        assertLt(strictGas, _measureSolidityExtremeQuantStrict());
    }

    function test_gas_extreme_vyper_nonzero_to_nonzero_metrics() public {
        uint256 rawGas = _measureVyperExtremeRawWarm();
        uint256 floorGas = _measureVyperExtremeQuantFloorWarm();
        uint256 strictGas = _measureVyperExtremeQuantStrictWarm();

        emit log_named_uint("warm_extreme_vyper_raw", rawGas);
        emit log_named_uint("warm_extreme_vyper_quant_floor", floorGas);
        emit log_named_uint("warm_extreme_vyper_quant_strict", strictGas);

        assertGt(rawGas, 0);
        assertGt(floorGas, 0);
        assertGt(strictGas, 0);
        assertLt(rawGas, _measureVyperExtremeRaw());
        assertLt(floorGas, _measureVyperExtremeQuantFloor());
        assertLt(strictGas, _measureVyperExtremeQuantStrict());
    }

    function test_showcase_inputs_fit_lanes() public pure {
        assertLe(REAL_STAKE_FLOOR >> REAL_SHIFT, REAL_AMOUNT_MAX);
        assertLe(REAL_STAKE_STRICT >> REAL_SHIFT, REAL_AMOUNT_MAX);
        assertLe(REAL_STAKE_STRICT_ALT >> REAL_SHIFT, REAL_AMOUNT_MAX);

        uint256[12] memory strictValues = _extremeStrictValues();
        uint256[12] memory strictValuesAlt = _extremeStrictValuesAlt();
        uint256[12] memory floorValues = _extremeFloorValues();
        for (uint256 i; i < EXT_LANES; ++i) {
            assertLe(strictValues[i] >> EXT_SHIFT, EXT_LANE_MAX);
            assertLe(strictValuesAlt[i] >> EXT_SHIFT, EXT_LANE_MAX);
            assertLe(floorValues[i] >> EXT_SHIFT, EXT_LANE_MAX);
        }
    }

    function _assertStaticcallEqual(address lhs, bytes4 lhsSelector, address rhs, bytes4 rhsSelector) internal view {
        _assertStaticcallEqual(lhs, lhsSelector, rhs, rhsSelector, "");
    }

    function _assertStaticcallEqual(
        address lhs,
        bytes4 lhsSelector,
        address rhs,
        bytes4 rhsSelector,
        bytes memory args
    ) internal view {
        (bool lhsOk, bytes memory lhsData) = lhs.staticcall(abi.encodePacked(lhsSelector, args));
        (bool rhsOk, bytes memory rhsData) = rhs.staticcall(abi.encodePacked(rhsSelector, args));
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

    function _extremeStrictValuesAlt() internal pure returns (uint256[12] memory values) {
        values[0] = (EXT_E0 + 1) << EXT_SHIFT;
        values[1] = (EXT_E1 + 1) << EXT_SHIFT;
        values[2] = (EXT_E2 + 1) << EXT_SHIFT;
        values[3] = (EXT_E3 + 1) << EXT_SHIFT;
        values[4] = (EXT_E4 + 1) << EXT_SHIFT;
        values[5] = (EXT_E5 + 1) << EXT_SHIFT;
        values[6] = (EXT_E6 + 1) << EXT_SHIFT;
        values[7] = (EXT_E7 + 1) << EXT_SHIFT;
        values[8] = (EXT_E8 + 1) << EXT_SHIFT;
        values[9] = (EXT_E9 + 1) << EXT_SHIFT;
        values[10] = (EXT_E10 + 1) << EXT_SHIFT;
        values[11] = (EXT_E11 + 1) << EXT_SHIFT;
    }

    function _savingsBps(uint256 rawGas, uint256 quantizedGas) internal pure returns (uint256) {
        return ((rawGas - quantizedGas) * 10_000) / rawGas;
    }

    function _measureSolidityRealRawStake() internal returns (uint256) {
        RawETHStakingShowcase raw = new RawETHStakingShowcase();
        raw.stake{value: REAL_STAKE_FLOOR}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealRawStakeWarm() internal returns (uint256) {
        RawETHStakingShowcase raw = new RawETHStakingShowcase();
        raw.stake{value: REAL_STAKE_FLOOR}();
        raw.stake{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantFloorStake() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stake{value: REAL_STAKE_FLOOR}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantFloorStakeWarm() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stake{value: REAL_STAKE_FLOOR}();
        quantized.stake{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantStrictStake() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stakeExact{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantStrictStakeWarm() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stakeExact{value: REAL_STAKE_STRICT}();
        quantized.stakeExact{value: REAL_STAKE_STRICT_ALT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealRawStake() internal returns (uint256) {
        IRawETHStakingShowcaseVyper raw = IRawETHStakingShowcaseVyper(deployCode("RawETHStakingShowcase.vy"));
        raw.stake{value: REAL_STAKE_FLOOR}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealRawStakeWarm() internal returns (uint256) {
        IRawETHStakingShowcaseVyper raw = IRawETHStakingShowcaseVyper(deployCode("RawETHStakingShowcase.vy"));
        raw.stake{value: REAL_STAKE_FLOOR}();
        raw.stake{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantFloorStake() internal returns (uint256) {
        IQuantizedETHStakingShowcaseVyper quantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));
        quantized.stake{value: REAL_STAKE_FLOOR}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantFloorStakeWarm() internal returns (uint256) {
        IQuantizedETHStakingShowcaseVyper quantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));
        quantized.stake{value: REAL_STAKE_FLOOR}();
        quantized.stake{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantStrictStake() internal returns (uint256) {
        IQuantizedETHStakingShowcaseVyper quantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));
        quantized.stake_exact{value: REAL_STAKE_STRICT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperRealQuantStrictStakeWarm() internal returns (uint256) {
        IQuantizedETHStakingShowcaseVyper quantized =
            IQuantizedETHStakingShowcaseVyper(deployCode("QuantizedETHStakingShowcase.vy"));
        quantized.stake_exact{value: REAL_STAKE_STRICT}();
        quantized.stake_exact{value: REAL_STAKE_STRICT_ALT}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeRaw() internal returns (uint256) {
        RawExtremePackingShowcase raw = new RawExtremePackingShowcase();
        uint256[12] memory values = _extremeFloorValues();
        raw.setExtremeRaw(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeRawWarm() internal returns (uint256) {
        RawExtremePackingShowcase raw = new RawExtremePackingShowcase();
        uint256[12] memory firstValues = _extremeFloorValues();
        uint256[12] memory secondValues = _extremeStrictValues();
        raw.setExtremeRaw(firstValues);
        raw.setExtremeRaw(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantFloor() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory values = _extremeFloorValues();
        quantized.setExtremeFloor(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantFloorWarm() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory firstValues = _extremeFloorValues();
        uint256[12] memory secondValues = _extremeStrictValues();
        quantized.setExtremeFloor(firstValues);
        quantized.setExtremeFloor(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantStrict() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory values = _extremeStrictValues();
        quantized.setExtremeStrict(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityExtremeQuantStrictWarm() internal returns (uint256) {
        QuantizedExtremePackingShowcase quantized = new QuantizedExtremePackingShowcase();
        uint256[12] memory firstValues = _extremeStrictValues();
        uint256[12] memory secondValues = _extremeStrictValuesAlt();
        quantized.setExtremeStrict(firstValues);
        quantized.setExtremeStrict(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeRaw() internal returns (uint256) {
        IRawExtremePackingShowcaseVyper raw = IRawExtremePackingShowcaseVyper(deployCode("RawExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeFloorValues();
        raw.set_extreme_raw(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeRawWarm() internal returns (uint256) {
        IRawExtremePackingShowcaseVyper raw = IRawExtremePackingShowcaseVyper(deployCode("RawExtremePackingShowcase.vy"));
        uint256[12] memory firstValues = _extremeFloorValues();
        uint256[12] memory secondValues = _extremeStrictValues();
        raw.set_extreme_raw(firstValues);
        raw.set_extreme_raw(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantFloor() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeFloorValues();
        quantized.set_extreme_floor(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantFloorWarm() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory firstValues = _extremeFloorValues();
        uint256[12] memory secondValues = _extremeStrictValues();
        quantized.set_extreme_floor(firstValues);
        quantized.set_extreme_floor(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantStrict() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory values = _extremeStrictValues();
        quantized.set_extreme_strict(values);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureVyperExtremeQuantStrictWarm() internal returns (uint256) {
        IQuantizedExtremePackingShowcaseVyper quantized =
            IQuantizedExtremePackingShowcaseVyper(deployCode("QuantizedExtremePackingShowcase.vy"));
        uint256[12] memory firstValues = _extremeStrictValues();
        uint256[12] memory secondValues = _extremeStrictValuesAlt();
        quantized.set_extreme_strict(firstValues);
        quantized.set_extreme_strict(secondValues);
        return uint256(vm.lastCallGas().gasTotalUsed);
    }
}
