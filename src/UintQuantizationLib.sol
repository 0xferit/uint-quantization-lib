// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title QuantizationLib
 * @author [0xferit](https://github.com/0xferit)
 * @custom:security-contact ferit@cryptolab.net
 * @notice Pure-function library for shift-based uint256 compression using a bundled config type.
 *
 *         The `Quant` value type packs a `(shift, targetBits)` scheme into a single `uint16`
 *         constant, allowing callers to define the compression config once and invoke methods
 *         on it. When `Quant` is declared as `constant`, the compiler folds the unpacking to
 *         zero-cost encoding at call sites.
 *
 *         Type layout (uint16):
 *           bits 0-7  → shift      (LSBs discarded during encoding)
 *           bits 8-15 → targetBits (bit-width of the encoded value)
 *
 *         Usage:
 *         ```solidity
 *         import {Quant, QuantizationLib} from "src/UintQuantizationLib.sol";
 *
 *         Quant private constant SCHEME = QuantizationLib.create(32, 24);
 *
 *         stored   = uint24(SCHEME.encode(value));
 *         restored = SCHEME.decode(stored);
 *         ```
 */
type Quant is uint16;

/// @notice Thrown when a value exceeds the maximum representable by the scheme.
error Quant__Overflow(uint256 value, uint256 max);

/// @notice Thrown by `encodeLossless` when a value is not aligned to the step size.
error Quant__NotAligned(uint256 value, uint256 stepSize);

/// @notice Thrown by `create` when the (shift, targetBits) pair is invalid.
error Quant__BadConfig(uint256 shift, uint256 targetBits);

library QuantizationLib {
    // -------------------------------------------------------------------------
    // Factory
    // -------------------------------------------------------------------------

    /// @notice Creates a `Quant` scheme from shift and targetBits.
    /// @dev    Reverts when shift >= 256, targetBits == 0, targetBits >= 256, or
    ///         shift + targetBits > 256. Any of these conditions would produce a scheme
    ///         where the computed max overflows or the step size is undefined.
    function create(uint256 shift_, uint256 targetBits_) internal pure returns (Quant) {
        if (shift_ >= 256 || targetBits_ == 0 || targetBits_ >= 256 || shift_ + targetBits_ > 256) {
            revert Quant__BadConfig(shift_, targetBits_);
        }
        // casting to uint16 is safe: create guard above ensures shift_ < 256 and targetBits_ < 256,
        // so (targetBits_ << 8) | shift_ <= 0xFF00 | 0xFF = 0xFFFF, which fits in uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        return Quant.wrap(uint16((targetBits_ << 8) | shift_));
    }

    // -------------------------------------------------------------------------
    // Accessors
    // -------------------------------------------------------------------------

    /// @notice Returns the shift component of the scheme (bits 0-7).
    function shift(Quant q) internal pure returns (uint256) {
        return uint256(Quant.unwrap(q)) & 0xFF;
    }

    /// @notice Returns the targetBits component of the scheme (bits 8-15).
    function targetBits(Quant q) internal pure returns (uint256) {
        return uint256(Quant.unwrap(q)) >> 8;
    }

    /// @notice Returns 2^shift: the quantization step size.
    function stepSize(Quant q) internal pure returns (uint256) {
        return uint256(1) << shift(q);
    }

    /// @notice Returns the maximum original value representable by this scheme.
    /// @dev    Safe when the scheme was created via `create`: shift + targetBits <= 256 and
    ///         targetBits < 256 guarantee the result fits in uint256.
    function max(Quant q) internal pure returns (uint256) {
        return ((uint256(1) << targetBits(q)) - 1) << shift(q);
    }

    // -------------------------------------------------------------------------
    // Encoding
    // -------------------------------------------------------------------------

    /// @notice Floor-encodes `value` by right-shifting. Reverts if value exceeds `max(q)`.
    function encode(Quant q, uint256 value) internal pure returns (uint256) {
        uint256 m = max(q);
        if (value > m) revert Quant__Overflow(value, m);
        return value >> shift(q);
    }

    /// @notice Strict mode: reverts if value exceeds max(q) or is not step-aligned.
    function encodeLossless(Quant q, uint256 value) internal pure returns (uint256) {
        uint256 m = max(q);
        if (value > m) revert Quant__Overflow(value, m);
        uint256 s = shift(q);
        uint256 step = uint256(1) << s;
        if (value & (step - 1) != 0) revert Quant__NotAligned(value, step);
        return value >> s;
    }

    // -------------------------------------------------------------------------
    // Decoding
    // -------------------------------------------------------------------------

    /// @notice Left-shifts `encoded` by shift, restoring discarded bits as zeros (lower bound).
    function decode(Quant q, uint256 encoded) internal pure returns (uint256) {
        unchecked {
            return encoded << shift(q);
        }
    }

    /// @notice Like `decode` but fills the discarded bits with ones (upper bound within the step).
    function decodeMax(Quant q, uint256 encoded) internal pure returns (uint256) {
        unchecked {
            uint256 s = shift(q);
            return (encoded << s) | ((uint256(1) << s) - 1);
        }
    }

    // -------------------------------------------------------------------------
    // Introspection / convenience
    // -------------------------------------------------------------------------

    /// @notice Returns the bits discarded during floor encoding (value mod stepSize).
    function remainder(Quant q, uint256 value) internal pure returns (uint256) {
        return value & ((uint256(1) << shift(q)) - 1);
    }

    /// @notice Returns true when `value` is exactly representable (step-aligned).
    function isLossless(Quant q, uint256 value) internal pure returns (bool) {
        return remainder(q, value) == 0;
    }

    /// @notice Returns true when `value <= max(q)`.
    function fits(Quant q, uint256 value) internal pure returns (bool) {
        return value <= max(q);
    }

    /// @notice Rounds `value` down to the nearest step boundary (clears low `shift` bits).
    function floor(Quant q, uint256 value) internal pure returns (uint256) {
        return value & ~((uint256(1) << shift(q)) - 1);
    }

    /// @notice Rounds `value` up to the nearest step boundary. Returns `value` unchanged when
    ///         shift is 0 or `value` is already aligned.
    /// @dev    Callers must ensure `value + stepSize - 1 <= type(uint256).max` to avoid overflow
    ///         on non-aligned inputs. This function does not perform that check.
    function ceil(Quant q, uint256 value) internal pure returns (uint256) {
        uint256 s = shift(q);
        if (s == 0) return value;
        uint256 mask = (uint256(1) << s) - 1;
        if (value & mask == 0) return value;
        return (value | mask) + 1;
    }
}

using QuantizationLib for Quant global;
