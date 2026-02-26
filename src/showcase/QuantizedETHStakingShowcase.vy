# SPDX-License-Identifier: MIT
# @version ^0.4.0

from src import UintQuantizationLib as lib

SHIFT: constant(uint256) = 16
AMOUNT_BITS: constant(uint256) = 96
AMOUNT_MASK: constant(uint256) = (1 << AMOUNT_BITS) - 1

STAKED_BITS: constant(uint256) = 64
STAKED_SHIFT: constant(uint256) = AMOUNT_BITS
STAKED_MASK: constant(uint256) = (1 << STAKED_BITS) - 1

COOLDOWN_BITS: constant(uint256) = 64
COOLDOWN_SHIFT: constant(uint256) = AMOUNT_BITS + STAKED_BITS
COOLDOWN_MASK: constant(uint256) = (1 << COOLDOWN_BITS) - 1

ACTIVE_SHIFT: constant(uint256) = AMOUNT_BITS + STAKED_BITS + COOLDOWN_BITS
COOLDOWN: constant(uint64) = 86400

packed_stake_by_user: HashMap[address, uint256]

@external
@payable
def stake():
    assert msg.value > 0, "ZeroAmount"

    encoded: uint256 = lib.encode_checked(msg.value, SHIFT, AMOUNT_BITS)
    now_ts: uint64 = convert(block.timestamp, uint64)
    cooldown_ends_at: uint64 = now_ts + COOLDOWN

    packed: uint256 = encoded
    packed = packed | (convert(now_ts, uint256) << STAKED_SHIFT)
    packed = packed | (convert(cooldown_ends_at, uint256) << COOLDOWN_SHIFT)
    packed = packed | (1 << ACTIVE_SHIFT)
    self.packed_stake_by_user[msg.sender] = packed

@external
@payable
def stake_exact():
    assert msg.value > 0, "ZeroAmount"

    encoded: uint256 = lib.encode_lossless_checked(msg.value, SHIFT, AMOUNT_BITS)
    now_ts: uint64 = convert(block.timestamp, uint64)
    cooldown_ends_at: uint64 = now_ts + COOLDOWN

    packed: uint256 = encoded
    packed = packed | (convert(now_ts, uint256) << STAKED_SHIFT)
    packed = packed | (convert(cooldown_ends_at, uint256) << COOLDOWN_SHIFT)
    packed = packed | (1 << ACTIVE_SHIFT)
    self.packed_stake_by_user[msg.sender] = packed

@external
def unstake():
    packed: uint256 = self.packed_stake_by_user[msg.sender]
    assert ((packed >> ACTIVE_SHIFT) & 1) == 1, "NoStake"

    payout: uint256 = lib.decode(packed & AMOUNT_MASK, SHIFT)
    self.packed_stake_by_user[msg.sender] = 0
    send(msg.sender, payout)

@external
@view
def encoded_stake(user: address) -> (uint96, uint64, uint64, bool):
    packed: uint256 = self.packed_stake_by_user[user]
    amount: uint96 = convert(packed & AMOUNT_MASK, uint96)
    staked_at: uint64 = convert((packed >> STAKED_SHIFT) & STAKED_MASK, uint64)
    cooldown_ends_at: uint64 = convert((packed >> COOLDOWN_SHIFT) & COOLDOWN_MASK, uint64)
    active: bool = ((packed >> ACTIVE_SHIFT) & 1) == 1
    return amount, staked_at, cooldown_ends_at, active

@external
@view
def get_stake(user: address) -> uint256:
    packed: uint256 = self.packed_stake_by_user[user]
    return lib.decode(packed & AMOUNT_MASK, SHIFT)

@external
@pure
def max_deposit() -> uint256:
    return lib.max_representable(SHIFT, AMOUNT_BITS)

@external
@pure
def stake_remainder(amount: uint256) -> uint256:
    return lib.remainder(amount, SHIFT)

@external
@pure
def is_stake_lossless(amount: uint256) -> bool:
    return lib.is_lossless(amount, SHIFT)
