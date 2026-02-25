# SPDX-License-Identifier: MIT
# @version ^0.4.0

value_a: public(uint256)
value_b: public(uint256)

@external
def set_pair(a: uint256, b: uint256):
    self.value_a = a
    self.value_b = b
