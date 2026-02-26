# SPDX-License-Identifier: MIT
# @version ^0.4.0
# @notice Thin harness that re-exports every UintQuantizationLib function as @external @pure
#         so Foundry can deploy this contract and Solidity tests can call into it.

from src import UintQuantizationLib as lib

@external
@pure
def encode(input_value: uint256, shift_bits: uint256) -> uint256:
    return lib.encode(input_value, shift_bits)

@external
@pure
def decode(compressed: uint256, shift_bits: uint256) -> uint256:
    return lib.decode(compressed, shift_bits)

@external
@pure
def step_size(shift_bits: uint256) -> uint256:
    return lib.step_size(shift_bits)

@external
@pure
def remainder(input_value: uint256, shift_bits: uint256) -> uint256:
    return lib.remainder(input_value, shift_bits)

@external
@pure
def is_lossless(input_value: uint256, shift_bits: uint256) -> bool:
    return lib.is_lossless(input_value, shift_bits)

@external
@pure
def max_representable(shift_bits: uint256, target_bits: uint256) -> uint256:
    return lib.max_representable(shift_bits, target_bits)

@external
@pure
def encode_checked(input_value: uint256, shift_bits: uint256, target_bits: uint256) -> uint256:
    return lib.encode_checked(input_value, shift_bits, target_bits)

@external
@pure
def encode_lossless(input_value: uint256, shift_bits: uint256) -> uint256:
    return lib.encode_lossless(input_value, shift_bits)

@external
@pure
def encode_lossless_checked(input_value: uint256, shift_bits: uint256, target_bits: uint256) -> uint256:
    return lib.encode_lossless_checked(input_value, shift_bits, target_bits)
