// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title UintQuantizationLib
 * @author [0xferit](https://github.com/0xferit)
 * @custom:security-contact ferit@cryptolab.net
 * @notice Pure-function library for shift-based uint256 compression using a bundled config type.
 *
 *         The `Quant` value type packs a `(discardedBitWidth, encodedBitWidth)` scheme into a single `uint16`,
 *         allowing callers to define the compression config once and invoke methods on it.
 *         Type layout (uint16):
 *           bits 0-7  → discardedBitWidth (LSBs discarded during encoding)
 *           bits 8-15 → encodedBitWidth   (bit-width of the encoded value)
 *
 *         Usage:
 *         ```solidity
 *         import {Quant, UintQuantizationLib as QuantLib} from "src/UintQuantizationLib.sol";
 *
 *         Quant private immutable SCHEME = QuantLib.create(32, 24);
 *
 *         stored   = uint24(SCHEME.encode(value));
 *         restored = SCHEME.decode(stored);
 *         ```
 */
type Quant is uint16;

/// @notice Thrown when a value exceeds the maximum representable by the scheme.
error Overflow(uint256 value, uint256 max);

/// @notice Thrown by `encode` (precise mode) when a value is not aligned to the step size.
error NotAligned(uint256 value, uint256 stepSize);

/// @notice Thrown by `create` when the (discardedBitWidth, encodedBitWidth) pair is invalid.
error BadConfig(uint256 discardedBitWidth, uint256 encodedBitWidth);

library UintQuantizationLib {
    string internal constant VERSION = "1.0.0";

    // -------------------------------------------------------------------------
    // Factory
    // -------------------------------------------------------------------------

    /// @notice Creates a `Quant` scheme from discardedBitWidth and encodedBitWidth.
    /// @dev    Reverts when discardedBitWidth >= 256, encodedBitWidth == 0, encodedBitWidth >= 256, or
    ///         discardedBitWidth + encodedBitWidth > 256. Any of these conditions would produce a scheme
    ///         where the computed max overflows or the step size is undefined.
    function create(uint256 discardedBitWidth_, uint256 encodedBitWidth_) internal pure returns (Quant) {
        if (
            discardedBitWidth_ >= 256 || encodedBitWidth_ == 0 || encodedBitWidth_ >= 256
                || discardedBitWidth_ + encodedBitWidth_ > 256
        ) {
            revert BadConfig(discardedBitWidth_, encodedBitWidth_);
        }
        // casting to uint16 is safe: create guard above ensures discardedBitWidth_ < 256 and encodedBitWidth_ < 256,
        // so (encodedBitWidth_ << 8) | discardedBitWidth_ <= 0xFF00 | 0xFF = 0xFFFF, which fits in uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        return Quant.wrap(uint16((encodedBitWidth_ << 8) | discardedBitWidth_));
    }

    // -------------------------------------------------------------------------
    // Accessors
    // -------------------------------------------------------------------------

    /// @notice Returns the discardedBitWidth component of the scheme (bits 0-7).
    function discardedBitWidth(Quant q) internal pure returns (uint256) {
        return uint256(Quant.unwrap(q)) & 0xFF;
    }

    /// @notice Returns the encodedBitWidth component of the scheme (bits 8-15).
    function encodedBitWidth(Quant q) internal pure returns (uint256) {
        return uint256(Quant.unwrap(q)) >> 8;
    }

    /// @notice Returns 2^discardedBitWidth: the quantization step size.
    function stepSize(Quant q) internal pure returns (uint256) {
        return uint256(1) << discardedBitWidth(q);
    }

    /// @notice Returns the maximum original value representable by this scheme.
    /// @dev    Safe when the scheme was created via `create`: discardedBitWidth + encodedBitWidth <= 256 and
    ///         encodedBitWidth < 256 guarantee the result fits in uint256.
    function max(Quant q) internal pure returns (uint256) {
        return ((uint256(1) << encodedBitWidth(q)) - 1) << discardedBitWidth(q);
    }

    // -------------------------------------------------------------------------
    // Encoding
    // -------------------------------------------------------------------------

    /// @notice Floor-encodes `value` by right-shifting. Reverts if value exceeds `max(q)`.
    function encode(Quant q, uint256 value) internal pure returns (uint256) {
        uint256 m = max(q);
        if (value > m) revert Overflow(value, m);
        return value >> discardedBitWidth(q);
    }

    /// @notice Encodes `value`. When `precise` is true, reverts if value is not step-aligned.
    ///         Always reverts if value exceeds `max(q)`.
    function encode(Quant q, uint256 value, bool precise) internal pure returns (uint256) {
        uint256 m = max(q);
        if (value > m) revert Overflow(value, m);
        uint256 s = discardedBitWidth(q);
        if (precise) {
            uint256 step = uint256(1) << s;
            if (value & (step - 1) != 0) revert NotAligned(value, step);
        }
        return value >> s;
    }

    // -------------------------------------------------------------------------
    // Decoding
    // -------------------------------------------------------------------------

    /// @notice Left-shifts `encoded` by discardedBitWidth, restoring discarded bits as zeros (lower bound).
    /// @dev    The caller must ensure `encoded < 2**encodedBitWidth(q)`. Passing a larger value
    ///         produces a result that may silently wrap or exceed the scheme's representable range.
    ///         Values returned by `encode` always satisfy this constraint.
    function decode(Quant q, uint256 encoded) internal pure returns (uint256) {
        unchecked {
            return encoded << discardedBitWidth(q);
        }
    }

    /// @notice Like `decode` but fills the discarded bits with ones (upper bound within the step).
    /// @dev    Same precondition as `decode`: `encoded` must be less than `2**encodedBitWidth(q)`.
    function decodeMax(Quant q, uint256 encoded) internal pure returns (uint256) {
        unchecked {
            uint256 s = discardedBitWidth(q);
            return (encoded << s) | ((uint256(1) << s) - 1);
        }
    }

    // -------------------------------------------------------------------------
    // Introspection / convenience
    // -------------------------------------------------------------------------

    /// @notice Returns the bits discarded during floor encoding (value mod stepSize).
    function remainder(Quant q, uint256 value) internal pure returns (uint256) {
        return value & ((uint256(1) << discardedBitWidth(q)) - 1);
    }

    /// @notice Returns true when `value` is exactly representable (step-aligned).
    function isAligned(Quant q, uint256 value) internal pure returns (bool) {
        return remainder(q, value) == 0;
    }

    /// @notice Returns true when `value <= max(q)`.
    function fits(Quant q, uint256 value) internal pure returns (bool) {
        return value <= max(q);
    }

    /// @notice Rounds `value` down to the nearest step boundary (clears low `discardedBitWidth` bits).
    function floor(Quant q, uint256 value) internal pure returns (uint256) {
        return value & ~((uint256(1) << discardedBitWidth(q)) - 1);
    }

    /// @notice Rounds `value` up to the nearest step boundary. Returns `value` unchanged when
    ///         discardedBitWidth is 0 or `value` is already aligned.
    /// @dev    Callers must ensure `value + stepSize - 1 <= type(uint256).max` to avoid overflow
    ///         on non-aligned inputs. This function does not perform that check.
    function ceil(Quant q, uint256 value) internal pure returns (uint256) {
        uint256 s = discardedBitWidth(q);
        if (s == 0) return value;
        uint256 mask = (uint256(1) << s) - 1;
        if (value & mask == 0) return value;
        return (value | mask) + 1;
    }
}

using UintQuantizationLib for Quant global;
