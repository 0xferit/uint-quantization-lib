# SPDX-License-Identifier: MIT
# @version ^0.4.0

raw_values: public(uint256[12])

@external
def set_extreme_raw(values: uint256[12]):
    for i: uint256 in range(12):
        self.raw_values[i] = values[i]
