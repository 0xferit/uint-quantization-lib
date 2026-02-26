# SPDX-License-Identifier: MIT
# @version ^0.4.0
# @title UintQuantizationLib
# @author 0xferit (https://github.com/0xferit)
# @notice Pure-function module for shift-based uint256 compression.
#
#         Compression is floor-quantization by right-shifting `shift_bits`.
#         This is lossy in general, but becomes lossless when inputs are
#         aligned to the step size `2^shift_bits`.
#
#         Usage:
#
#             from src import UintQuantizationLib as lib
#
#             SHIFT: constant(uint256) = 32
#
#             # Lossy mode
#             stored:   uint56  = uint56(lib.encode(value, SHIFT))
#             restored: uint256 = lib.decode(convert(stored, uint256), SHIFT)
#
#             # Lossless mode (reverts when inexact)
#             strict_stored: uint56 = uint56(lib.encode_lossless_checked(value, SHIFT, 56))

# ---------------------------------------------------------------------------
# Core encode / decode
# ---------------------------------------------------------------------------

@internal
@pure
def encode(input_value: uint256, shift_bits: uint256) -> uint256:
    """
    @notice Right-shifts `input_value` by `shift_bits`, discarding the N least significant bits.
    @dev    For shift_bits >= 256 the EVM returns 0 consistently; no revert is issued.
    """
    if shift_bits >= 256:
        return 0
    return input_value >> shift_bits

@internal
@pure
def decode(compressed: uint256, shift_bits: uint256) -> uint256:
    """
    @notice Left-shifts `compressed` by `shift_bits`, restoring discarded bits as zeros.
    @dev    For shift_bits >= 256 the EVM returns 0 consistently; no revert is issued.
            If `compressed << shift_bits` exceeds 2^256, high bits are silently truncated (standard
            EVM SHL behavior). Callers who need arithmetic (non-wrapping) bounds should ensure
            the shifted value fits in uint256 (e.g., via `max_representable` validation during
            encoding).
    """
    if shift_bits >= 256:
        return 0
    return compressed << shift_bits

# ---------------------------------------------------------------------------
# Introspection helpers
# ---------------------------------------------------------------------------

@internal
@pure
def step_size(shift_bits: uint256) -> uint256:
    """
    @notice Returns 2^shift_bits: the quantization step size.
    """
    assert shift_bits < 256, "UintQuantizationLib__InvalidShift"
    return 1 << shift_bits

@internal
@pure
def remainder(input_value: uint256, shift_bits: uint256) -> uint256:
    """
    @notice Returns the bits discarded by floor encoding.
    """
    assert shift_bits < 256, "UintQuantizationLib__InvalidShift"
    return input_value & ((1 << shift_bits) - 1)

@internal
@pure
def is_lossless(input_value: uint256, shift_bits: uint256) -> bool:
    """
    @notice Returns true when `input_value` is exactly representable at `shift_bits`.
    """
    assert shift_bits < 256, "UintQuantizationLib__InvalidShift"
    return (input_value & ((1 << shift_bits) - 1)) == 0

@internal
@pure
def max_representable(shift_bits: uint256, target_bits: uint256) -> uint256:
    """
    @notice Returns max original value encodable into `target_bits` bits without overflow.
    """
    assert target_bits < 256, "UintQuantizationLib__Overflow"
    assert shift_bits <= 256 - target_bits, "UintQuantizationLib__Overflow"
    return ((1 << target_bits) - 1) << shift_bits

# ---------------------------------------------------------------------------
# Checked variants
# ---------------------------------------------------------------------------

@internal
@pure
def encode_checked(input_value: uint256, shift_bits: uint256, target_bits: uint256) -> uint256:
    """
    @notice Like encode but reverts if the encoded result does not fit in `target_bits`.
    """
    assert target_bits < 256, "UintQuantizationLib__Overflow"
    compressed: uint256 = 0
    if shift_bits < 256:
        compressed = input_value >> shift_bits
    assert compressed >> target_bits == 0, "UintQuantizationLib__Overflow"
    return compressed

@internal
@pure
def encode_lossless(input_value: uint256, shift_bits: uint256) -> uint256:
    """
    @notice Strict encoding mode: reverts when `input_value` is not step-aligned.
    """
    assert shift_bits < 256, "UintQuantizationLib__InvalidShift"
    rem: uint256 = input_value & ((1 << shift_bits) - 1)
    assert rem == 0, "UintQuantizationLib__InexactInput"
    return input_value >> shift_bits

@internal
@pure
def encode_lossless_checked(input_value: uint256, shift_bits: uint256, target_bits: uint256) -> uint256:
    """
    @notice Strict + width-checked mode.
    """
    assert target_bits < 256, "UintQuantizationLib__Overflow"
    compressed: uint256 = self.encode_lossless(input_value, shift_bits)
    assert compressed >> target_bits == 0, "UintQuantizationLib__Overflow"
    return compressed
