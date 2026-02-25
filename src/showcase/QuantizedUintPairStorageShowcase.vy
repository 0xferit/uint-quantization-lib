# SPDX-License-Identifier: MIT
# @version ^0.4.0

from src import UintQuantizationLib as lib

SHIFT: constant(uint256) = 40
WIDTH: constant(uint256) = 56
LANE_MASK: constant(uint256) = (1 << WIDTH) - 1

packed_pair: public(uint256)

@external
def set_pair_floor(a: uint256, b: uint256):
    encoded_a: uint256 = lib.encode_checked(a, SHIFT, WIDTH)
    encoded_b: uint256 = lib.encode_checked(b, SHIFT, WIDTH)
    self.packed_pair = encoded_a | (encoded_b << WIDTH)

@external
def set_pair_strict(a: uint256, b: uint256):
    encoded_a: uint256 = lib.encode_lossless_checked(a, SHIFT, WIDTH)
    encoded_b: uint256 = lib.encode_lossless_checked(b, SHIFT, WIDTH)
    self.packed_pair = encoded_a | (encoded_b << WIDTH)

@external
@view
def encoded_pair() -> (uint256, uint256):
    encoded_a: uint256 = self.packed_pair & LANE_MASK
    encoded_b: uint256 = (self.packed_pair >> WIDTH) & LANE_MASK
    return encoded_a, encoded_b

@external
@view
def decode_floor() -> (uint256, uint256):
    encoded_a: uint256 = self.packed_pair & LANE_MASK
    encoded_b: uint256 = (self.packed_pair >> WIDTH) & LANE_MASK
    lower_a: uint256 = lib.decode(encoded_a, SHIFT)
    lower_b: uint256 = lib.decode(encoded_b, SHIFT)
    return lower_a, lower_b

@external
@view
def decode_ceil() -> (uint256, uint256):
    encoded_a: uint256 = self.packed_pair & LANE_MASK
    encoded_b: uint256 = (self.packed_pair >> WIDTH) & LANE_MASK
    upper_a: uint256 = lib.decode_ceil(encoded_a, SHIFT)
    upper_b: uint256 = lib.decode_ceil(encoded_b, SHIFT)
    return upper_a, upper_b
