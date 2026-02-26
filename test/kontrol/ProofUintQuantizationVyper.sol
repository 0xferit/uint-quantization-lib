// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UintQuantizationLib} from "src/UintQuantizationLib.sol";
import {ProofAssumptions} from "test/kontrol/ProofAssumptions.sol";

interface IUintQuantizationLibVyperProof {
    function encode(uint256 value, uint256 shift) external pure returns (uint256);
    function encode_ceil(uint256 value, uint256 shift) external pure returns (uint256);
    function decode(uint256 compressed, uint256 shift) external pure returns (uint256);
    function decode_ceil(uint256 compressed, uint256 shift) external pure returns (uint256);
    function step_size(uint256 shift) external pure returns (uint256);
    function remainder(uint256 value, uint256 shift) external pure returns (uint256);
    function is_lossless(uint256 value, uint256 shift) external pure returns (bool);
    function max_representable(uint256 shift, uint256 targetBits) external pure returns (uint256);
    function encode_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256);
    function encode_ceil_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256);
    function encode_lossless(uint256 value, uint256 shift) external pure returns (uint256);
    function encode_lossless_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256);
}

contract UintQuantizationSolidityMirrorProof {
    using UintQuantizationLib for uint256;

    function encode(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encode(shift);
    }

    function encode_ceil(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encodeCeil(shift);
    }

    function decode(uint256 compressed, uint256 shift) external pure returns (uint256) {
        return compressed.decode(shift);
    }

    function decode_ceil(uint256 compressed, uint256 shift) external pure returns (uint256) {
        return compressed.decodeCeil(shift);
    }

    function step_size(uint256 shift) external pure returns (uint256) {
        return UintQuantizationLib.stepSize(shift);
    }

    function remainder(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.remainder(shift);
    }

    function is_lossless(uint256 value, uint256 shift) external pure returns (bool) {
        return UintQuantizationLib.isLossless(value, shift);
    }

    function max_representable(uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return UintQuantizationLib.maxRepresentable(shift, targetBits);
    }

    function encode_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeChecked(shift, targetBits);
    }

    function encode_ceil_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeCeilChecked(shift, targetBits);
    }

    function encode_lossless(uint256 value, uint256 shift) external pure returns (uint256) {
        return value.encodeLossless(shift);
    }

    function encode_lossless_checked(uint256 value, uint256 shift, uint256 targetBits) external pure returns (uint256) {
        return value.encodeLosslessChecked(shift, targetBits);
    }
}

contract ProofUintQuantizationVyper is ProofAssumptions {
    IUintQuantizationLibVyperProof internal vyperHarness;
    IUintQuantizationLibVyperProof internal solidityMirror;

    function setUp() public {
        vyperHarness = IUintQuantizationLibVyperProof(deployCode("UintQuantizationLibVyperHarness.vy"));
        solidityMirror = IUintQuantizationLibVyperProof(address(new UintQuantizationSolidityMirrorProof()));
    }

    function prove_parity_encode(uint256 value, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode.selector, value, shift));
    }

    function prove_parity_encode_ceil(uint256 value, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode_ceil.selector, value, shift));
    }

    function prove_parity_decode(uint256 compressed, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.decode.selector, compressed, shift));
    }

    function prove_parity_decode_ceil(uint256 compressed, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.decode_ceil.selector, compressed, shift));
    }

    function prove_parity_step_size(uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.step_size.selector, shift));
    }

    function prove_parity_remainder(uint256 value, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.remainder.selector, value, shift));
    }

    function prove_parity_is_lossless(uint256 value, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.is_lossless.selector, value, shift));
    }

    function prove_parity_max_representable(uint256 shift, uint256 targetBits) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.max_representable.selector, shift, targetBits));
    }

    function prove_parity_encode_checked(uint256 value, uint256 shift, uint256 targetBits) public view {
        _assertParity(
            abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode_checked.selector, value, shift, targetBits)
        );
    }

    function prove_parity_encode_ceil_checked(uint256 value, uint256 shift, uint256 targetBits) public view {
        _assertParity(
            abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode_ceil_checked.selector, value, shift, targetBits)
        );
    }

    function prove_parity_encode_lossless(uint256 value, uint256 shift) public view {
        _assertParity(abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode_lossless.selector, value, shift));
    }

    function prove_parity_encode_lossless_checked(uint256 value, uint256 shift, uint256 targetBits) public view {
        _assertParity(
            abi.encodeWithSelector(IUintQuantizationLibVyperProof.encode_lossless_checked.selector, value, shift, targetBits)
        );
    }

    function _assertParity(bytes memory callData) internal view {
        (bool soliditySuccess, bytes memory solidityData) = address(solidityMirror).staticcall(callData);
        (bool vyperSuccess, bytes memory vyperData) = address(vyperHarness).staticcall(callData);
        assertEq(soliditySuccess, vyperSuccess, "status mismatch");
        if (soliditySuccess) {
            assertEq(solidityData, vyperData, "return mismatch");
        }
    }
}
