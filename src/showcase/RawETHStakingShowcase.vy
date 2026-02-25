# SPDX-License-Identifier: MIT
# @version ^0.4.0

COOLDOWN: constant(uint64) = 86400

AMOUNT_BITS: constant(uint256) = 128
AMOUNT_MASK: constant(uint256) = (1 << AMOUNT_BITS) - 1

STAKED_BITS: constant(uint256) = 64
STAKED_SHIFT: constant(uint256) = AMOUNT_BITS

COOLDOWN_BITS: constant(uint256) = 64
COOLDOWN_SHIFT: constant(uint256) = AMOUNT_BITS + STAKED_BITS

# Mirrors Solidity raw layout economics:
# - packed_stake_by_user: slot with amount(128) + staked_at(64) + cooldown_ends_at(64)
# - active_by_user: separate slot for bool
packed_stake_by_user: HashMap[address, uint256]
active_by_user: HashMap[address, bool]

@external
@payable
def stake():
    assert msg.value > 0, "ZeroAmount"

    now_ts: uint64 = convert(block.timestamp, uint64)
    cooldown_ends_at: uint64 = now_ts + COOLDOWN

    packed: uint256 = convert(convert(msg.value, uint128), uint256)
    packed = packed | (convert(now_ts, uint256) << STAKED_SHIFT)
    packed = packed | (convert(cooldown_ends_at, uint256) << COOLDOWN_SHIFT)

    self.packed_stake_by_user[msg.sender] = packed
    self.active_by_user[msg.sender] = True

@external
def unstake():
    assert self.active_by_user[msg.sender], "NoStake"

    packed: uint256 = self.packed_stake_by_user[msg.sender]
    amount: uint256 = packed & AMOUNT_MASK

    self.packed_stake_by_user[msg.sender] = 0
    self.active_by_user[msg.sender] = False
    send(msg.sender, amount)
