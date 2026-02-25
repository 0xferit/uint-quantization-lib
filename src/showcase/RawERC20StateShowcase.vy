# SPDX-License-Identifier: MIT
# @version ^0.4.0

total_supply: public(uint256)
treasury_balance: public(uint256)
fee_accumulator: public(uint256)
nonce_cursor: public(uint256)

@external
def set_state_raw(_total_supply: uint256, _treasury_balance: uint256, _fee_accumulator: uint256, _nonce_cursor: uint256):
    self.total_supply = _total_supply
    self.treasury_balance = _treasury_balance
    self.fee_accumulator = _fee_accumulator
    self.nonce_cursor = _nonce_cursor
