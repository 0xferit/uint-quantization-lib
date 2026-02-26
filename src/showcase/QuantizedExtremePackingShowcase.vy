# SPDX-License-Identifier: MIT
# @version ^0.4.0

from src import UintQuantizationLib as lib

SHIFT: constant(uint256) = 8
WIDTH: constant(uint256) = 20
LANE_MASK: constant(uint256) = (1 << WIDTH) - 1

packed_extreme: public(uint256)

@external
def set_extreme_floor(values: uint256[12]):
    p: uint256 = 0
    for i: uint256 in range(12):
        lane: uint256 = lib.encode(values[i], SHIFT) & LANE_MASK
        p = p | (lane << (i * WIDTH))
    self.packed_extreme = p

@external
def set_extreme_strict(values: uint256[12]):
    p: uint256 = 0
    for i: uint256 in range(12):
        lane: uint256 = lib.encode_lossless_checked(values[i], SHIFT, WIDTH)
        p = p | (lane << (i * WIDTH))
    self.packed_extreme = p

@external
@view
def encoded_extreme() -> uint256[12]:
    lanes: uint256[12] = empty(uint256[12])
    p: uint256 = self.packed_extreme
    for i: uint256 in range(12):
        lanes[i] = (p >> (i * WIDTH)) & LANE_MASK
    return lanes

@external
@view
def decode_extreme_floor() -> uint256[12]:
    values: uint256[12] = empty(uint256[12])
    p: uint256 = self.packed_extreme
    for i: uint256 in range(12):
        values[i] = lib.decode((p >> (i * WIDTH)) & LANE_MASK, SHIFT)
    return values
