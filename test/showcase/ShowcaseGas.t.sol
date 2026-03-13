// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    QuantizedETHStakingShowcase,
    QuantizedExtremePackingShowcase,
    RawETHStakingShowcase,
    RawExtremePackingShowcase
} from "src/showcase/ShowcaseSolidityFixtures.sol";

contract ShowcaseGasTest is Test {
    uint256 internal constant REAL_SHIFT = 16;
    uint256 internal constant REAL_AMOUNT_BITS = 96;
    uint256 internal constant REAL_AMOUNT_MAX = (uint256(1) << REAL_AMOUNT_BITS) - 1;

    uint256 internal constant EXT_SHIFT = 8;
    uint256 internal constant EXT_WIDTH = 20;
    uint256 internal constant EXT_LANES = 12;
    uint256 internal constant EXT_LANE_MAX = (uint256(1) << EXT_WIDTH) - 1;

    uint256 internal constant MIN_REAL_SAVINGS_BPS = 3_200; // >=32%

    uint256 internal constant REAL_STAKE_STRICT = uint256(2_500_000) << REAL_SHIFT;
    uint256 internal constant REAL_STAKE_STRICT_ALT = uint256(2_750_000) << REAL_SHIFT;
    uint256 internal constant REAL_STAKE_FLOOR = REAL_STAKE_STRICT + 321;

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

    function test_gas_real_life_solidity_zero_to_nonzero_savings_ge_target() public {
        uint256 rawGas = _measureSolidityRealRawStake();
        uint256 floorGas = _measureSolidityRealQuantFloorStake();
        uint256 strictGas = _measureSolidityRealQuantStrictStake();

        assertGt(rawGas, floorGas);
        assertGt(rawGas, strictGas);
        assertGe(_savingsBps(rawGas, floorGas), MIN_REAL_SAVINGS_BPS);
        assertGe(_savingsBps(rawGas, strictGas), MIN_REAL_SAVINGS_BPS);
    }

    /// @notice Logs extreme-packing gas numbers for documentation. Not a regression gate:
    ///         the savings are a property of the 12:1 slot ratio, not the library's efficiency.
    function test_gas_extreme_solidity_zero_to_nonzero_logs() public {
        uint256 rawGas = _measureSolidityExtremeRaw();
        uint256 floorGas = _measureSolidityExtremeQuantFloor();
        uint256 strictGas = _measureSolidityExtremeQuantStrict();

        emit log_named_uint("extreme raw gas", rawGas);
        emit log_named_uint("extreme floor gas", floorGas);
        emit log_named_uint("extreme strict gas", strictGas);
        emit log_named_uint("extreme floor savings bps", _savingsBps(rawGas, floorGas));
        emit log_named_uint("extreme strict savings bps", _savingsBps(rawGas, strictGas));
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

    function _measureSolidityRealQuantFloorStake() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stake{value: REAL_STAKE_FLOOR}();
        return uint256(vm.lastCallGas().gasTotalUsed);
    }

    function _measureSolidityRealQuantStrictStake() internal returns (uint256) {
        QuantizedETHStakingShowcase quantized = new QuantizedETHStakingShowcase();
        quantized.stakeExact{value: REAL_STAKE_STRICT}();
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
}
