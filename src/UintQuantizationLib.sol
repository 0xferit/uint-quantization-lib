// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title UintQuantizationLib
 * @author [0xferit](https://github.com/0xferit)
 * @custom:security-contact ferit@cryptolab.net
 * @notice Pure-function library for shift-based uint256 compression.
 *
 *         Compression is floor-quantization by right-shifting `shift` bits.
 *         This is lossy in general, but becomes lossless when inputs are
 *         aligned to the step size `2^shift`.
 *
 *         Usage:
 *         ```solidity
 *         using UintQuantizationLib for uint256;
 *
 *         uint256 private constant SHIFT = 32;
 *
 *         // Lossy/floor mode
 *         stored   = uint56(value.encode(SHIFT));
 *         restored = uint256(stored).decode(SHIFT);
 *
 *         // Lossless/strict mode (reverts when value is not step-aligned)
 *         stored = uint56(value.encodeLosslessChecked(SHIFT, 56));
 *         ```
 */
library UintQuantizationLib {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the encoded value does not fit in `targetBits`.
    ///         Also thrown by `maxRepresentable` when `targetBits >= 256` or
    ///         `shift + targetBits > 256`; in that case `encoded` carries `shift + targetBits`
    ///         when representable, otherwise `type(uint256).max`; `targetBits` carries 256 as the
    ///         hard limit.
    error UintQuantizationLib__Overflow(uint256 encoded, uint256 targetBits);

    /// @notice Thrown when `shift` is >= 256, which produces undefined results for uint256
    ///         operands in helper functions.
    ///         `encode`, `decode`, and `encodeChecked` are exempt: the EVM naturally returns 0
    ///         for shifts >= 256. Strict helpers like `encodeLossless` validate shift to prevent
    ///         silent data loss.
    error UintQuantizationLib__InvalidShift(uint256 shift);

    /// @notice Thrown by strict lossless encode helpers when `value` is not aligned to `2^shift`.
    error UintQuantizationLib__InexactInput(uint256 value, uint256 shift, uint256 remainder);

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    function _requireValidShift(uint256 shift) private pure {
        if (shift >= 256) revert UintQuantizationLib__InvalidShift(shift);
    }

    function _sumOrMax(uint256 a, uint256 b) private pure returns (uint256) {
        // Saturate on overflow so callers can deterministically surface custom errors
        // instead of a Solidity panic from checked arithmetic.
        unchecked {
            uint256 sum = a + b;
            if (sum < a) return type(uint256).max;
            return sum;
        }
    }

    function _remainderUnchecked(uint256 value, uint256 shift) private pure returns (uint256) {
        return value & ((uint256(1) << shift) - 1);
    }

    // -------------------------------------------------------------------------
    // Core encode / decode
    // -------------------------------------------------------------------------

    /// @notice Right-shifts `value` by `shift`, discarding the N least significant bits
    ///         (floor quantization). The caller must narrow the result to the target storage
    ///         type via explicit cast.
    /// @dev    For shift >= 256 the EVM returns 0 consistently; no revert is issued.
    /// @param value  Original value.
    /// @param shift  Number of least-significant bits to discard.
    /// @return Compressed representation.
    function encode(uint256 value, uint256 shift) internal pure returns (uint256) {
        unchecked {
            return value >> shift;
        }
    }

    /// @notice Right-shifts `value` by `shift`, rounding up (ceiling quantization) if any bits
    ///         were discarded. Use when the stored value must never under-represent the original.
    /// @param value  Original value.
    /// @param shift  Number of least-significant bits to discard. Must be < 256.
    /// @return Compressed representation, rounded up toward the next integer.
    function encodeCeil(uint256 value, uint256 shift) internal pure returns (uint256) {
        _requireValidShift(shift);
        uint256 rem = _remainderUnchecked(value, shift);
        uint256 roundUp;
        assembly ("memory-safe") {
            // iszero(iszero(x)) converts any nonzero value to 1 and zero to 0 without a JUMPI.
            roundUp := iszero(iszero(rem))
        }
        // The addition cannot overflow: when shift >= 1, value >> shift <= max/2.
        // When shift == 0, rem == 0 so roundUp == 0.
        unchecked {
            return (value >> shift) + roundUp;
        }
    }

    /// @notice Left-shifts `compressed` by `shift`, restoring discarded bits as zeros.
    ///         Gives the minimum possible original value (lower bound).
    /// @dev    For shift >= 256 the EVM returns 0 consistently; no revert is issued.
    /// @param compressed  Previously encoded value.
    /// @param shift       Number of bits that were discarded during encoding.
    /// @return Lower bound on the original value.
    function decode(uint256 compressed, uint256 shift) internal pure returns (uint256) {
        unchecked {
            return compressed << shift;
        }
    }

    /// @notice Left-shifts `compressed` by `shift` and fills discarded bit positions with ones.
    ///         Gives the maximum possible original value that encodes to `compressed`.
    ///         Satisfies: decode(encode(v, shift), shift) <= v <= decodeCeil(encode(v, shift), shift).
    /// @dev    Mirrors EVM shift semantics: if `compressed << shift` exceeds 256 bits, high bits
    ///         are truncated. Callers that require arithmetic (non-wrapping) bounds must ensure
    ///         the shifted value fits in uint256.
    /// @param compressed  Previously encoded value.
    /// @param shift       Number of bits that were discarded during encoding. Must be < 256.
    /// @return Upper bound on the original value.
    function decodeCeil(uint256 compressed, uint256 shift) internal pure returns (uint256) {
        _requireValidShift(shift);
        return (compressed << shift) | ((uint256(1) << shift) - 1);
    }

    // -------------------------------------------------------------------------
    // Introspection helpers
    // -------------------------------------------------------------------------

    /// @notice Returns 2^shift: the quantization step size. Any two original values within one
    ///         step of each other encode to the same stored value.
    function stepSize(uint256 shift) internal pure returns (uint256) {
        _requireValidShift(shift);
        return uint256(1) << shift;
    }

    /// @notice Returns the truncation remainder: the bits discarded during floor encoding.
    ///         Equivalent to `value mod 2^shift`, or `value - decode(encode(value, shift), shift)`.
    function remainder(uint256 value, uint256 shift) internal pure returns (uint256) {
        _requireValidShift(shift);
        return _remainderUnchecked(value, shift);
    }

    /// @notice Returns true when `value` is exactly representable at `shift`, i.e. no precision is
    ///         lost by floor encoding. Equivalent to `remainder(value, shift) == 0`.
    function isLossless(uint256 value, uint256 shift) internal pure returns (bool) {
        _requireValidShift(shift);
        return _remainderUnchecked(value, shift) == 0;
    }

    /// @notice Returns the maximum original value that can be encoded into `targetBits` bits
    ///         without overflow.
    function maxRepresentable(uint256 shift, uint256 targetBits) internal pure returns (uint256) {
        // targetBits >= 256 causes (uint256(1) << targetBits) to wrap to 0, making the result wrong.
        // shift + targetBits > 256 causes the final left-shift to silently discard high bits.
        uint256 bitsRequired = _sumOrMax(shift, targetBits);
        if (targetBits >= 256 || bitsRequired > 256) {
            revert UintQuantizationLib__Overflow(bitsRequired, 256);
        }
        return ((uint256(1) << targetBits) - 1) << shift;
    }

    // -------------------------------------------------------------------------
    // Checked variants
    // -------------------------------------------------------------------------

    /// @notice Like `encode` but reverts if the encoded result does not fit in `targetBits`.
    ///         Reverts when `targetBits >= 256`.
    /// @dev    Mirrors `encode` semantics for large shifts: for `shift >= 256`, the EVM
    ///         right-shift returns 0 and this function succeeds if `targetBits < 256`.
    ///         This is intentionally asymmetric with `encodeLossless`: `encodeChecked` only
    ///         validates overflow (targetBits), not shift validity. Use `encodeLossless` or
    ///         `encodeLosslessChecked` when strict shift validation is required.
    function encodeChecked(uint256 value, uint256 shift, uint256 targetBits) internal pure returns (uint256) {
        if (targetBits >= 256) {
            revert UintQuantizationLib__Overflow(targetBits, 256);
        }
        uint256 compressed = value >> shift;
        if (compressed >> targetBits != 0) {
            revert UintQuantizationLib__Overflow(compressed, targetBits);
        }
        return compressed;
    }

    /// @notice Like `encodeCeil` but reverts if the ceiling-rounded result does not fit in
    ///         `targetBits`. Reverts when `targetBits >= 256`.
    function encodeCeilChecked(uint256 value, uint256 shift, uint256 targetBits) internal pure returns (uint256) {
        if (targetBits >= 256) {
            revert UintQuantizationLib__Overflow(targetBits, 256);
        }
        uint256 compressed = encodeCeil(value, shift);
        if (compressed >> targetBits != 0) {
            revert UintQuantizationLib__Overflow(compressed, targetBits);
        }
        return compressed;
    }

    /// @notice Strict encoding mode: succeeds only if floor encoding is lossless
    ///         (`value` is step-aligned), otherwise reverts with `UintQuantizationLib__InexactInput`.
    /// @dev    Unlike `encode` and `encodeChecked`, this function validates `shift < 256` to prevent
    ///         silent data loss from invalid shifts. Use this when strict validation is required.
    function encodeLossless(uint256 value, uint256 shift) internal pure returns (uint256) {
        _requireValidShift(shift);
        uint256 rem = _remainderUnchecked(value, shift);
        if (rem != 0) {
            revert UintQuantizationLib__InexactInput(value, shift, rem);
        }
        return value >> shift;
    }

    /// @notice Strict + width-checked mode: same as `encodeLossless` and also requires the encoded
    ///         value to fit in `targetBits`. Reverts when `targetBits >= 256`.
    function encodeLosslessChecked(uint256 value, uint256 shift, uint256 targetBits)
        internal
        pure
        returns (uint256)
    {
        if (targetBits >= 256) {
            revert UintQuantizationLib__Overflow(targetBits, 256);
        }
        uint256 compressed = encodeLossless(value, shift);
        if (compressed >> targetBits != 0) {
            revert UintQuantizationLib__Overflow(compressed, targetBits);
        }
        return compressed;
    }
}
