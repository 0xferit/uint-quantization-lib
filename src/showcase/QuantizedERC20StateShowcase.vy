# SPDX-License-Identifier: MIT
# @version ^0.4.0

from src import UintQuantizationLib as lib

SHIFT: constant(uint256) = 16
WIDTH: constant(uint256) = 40
LANE_MASK: constant(uint256) = (1 << WIDTH) - 1

packed_state: public(uint256)

@external
def set_state_floor(_total_supply: uint256, _treasury_balance: uint256, _fee_accumulator: uint256, _nonce_cursor: uint256):
    e0: uint256 = lib.encode_checked(_total_supply, SHIFT, WIDTH)
    e1: uint256 = lib.encode_checked(_treasury_balance, SHIFT, WIDTH)
    e2: uint256 = lib.encode_checked(_fee_accumulator, SHIFT, WIDTH)
    e3: uint256 = lib.encode_checked(_nonce_cursor, SHIFT, WIDTH)
    self.packed_state = e0 | (e1 << 40) | (e2 << 80) | (e3 << 120)

@external
def set_state_strict(_total_supply: uint256, _treasury_balance: uint256, _fee_accumulator: uint256, _nonce_cursor: uint256):
    e0: uint256 = lib.encode_lossless_checked(_total_supply, SHIFT, WIDTH)
    e1: uint256 = lib.encode_lossless_checked(_treasury_balance, SHIFT, WIDTH)
    e2: uint256 = lib.encode_lossless_checked(_fee_accumulator, SHIFT, WIDTH)
    e3: uint256 = lib.encode_lossless_checked(_nonce_cursor, SHIFT, WIDTH)
    self.packed_state = e0 | (e1 << 40) | (e2 << 80) | (e3 << 120)

@external
@view
def encoded_state() -> (uint256, uint256, uint256, uint256):
    p: uint256 = self.packed_state
    return (
        p & LANE_MASK,
        (p >> 40) & LANE_MASK,
        (p >> 80) & LANE_MASK,
        (p >> 120) & LANE_MASK,
    )

@external
@view
def decode_state_floor() -> (uint256, uint256, uint256, uint256):
    p: uint256 = self.packed_state
    return (
        lib.decode(p & LANE_MASK, SHIFT),
        lib.decode((p >> 40) & LANE_MASK, SHIFT),
        lib.decode((p >> 80) & LANE_MASK, SHIFT),
        lib.decode((p >> 120) & LANE_MASK, SHIFT),
    )

@external
@view
def decode_state_ceil() -> (uint256, uint256, uint256, uint256):
    p: uint256 = self.packed_state
    return (
        lib.decode_ceil(p & LANE_MASK, SHIFT),
        lib.decode_ceil((p >> 40) & LANE_MASK, SHIFT),
        lib.decode_ceil((p >> 80) & LANE_MASK, SHIFT),
        lib.decode_ceil((p >> 120) & LANE_MASK, SHIFT),
    )
