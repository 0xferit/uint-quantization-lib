## [7.0.0](https://github.com/0xferit/uint-quantization-lib/compare/v6.1.1...v7.0.0) (2026-03-13)

### Features

* make decode/decodeMax checked by default, add unchecked variants ([3b82e83](https://github.com/0xferit/uint-quantization-lib/commit/3b82e834ba32b2164b716672c8b76aeee9977543))

## [6.1.1](https://github.com/0xferit/uint-quantization-lib/compare/v6.1.0...v6.1.1) (2026-03-13)

## [6.1.0](https://github.com/0xferit/uint-quantization-lib/compare/v6.0.3...v6.1.0) (2026-03-13)

### Features

* add isValid, fitsEncoded helpers and fix ceil overflow ([903287c](https://github.com/0xferit/uint-quantization-lib/commit/903287c19bd7b97b4d8f096a1dce5479638805f5))

## 1.0.1 through 6.0.3 (2026-03-13)

Versions 1.0.1 through 6.0.3 were created by release pipeline iteration during initial CI setup. The library was renamed from `shift`/`targetBits` to `discardedBitWidth`/`encodedBitWidth` (breaking API change, hence the major bumps). No functional changes between these versions beyond the rename and CI fixes. See [v1.0.0...v6.0.3](https://github.com/0xferit/uint-quantization-lib/compare/v1.0.0...v6.0.3) for the full diff.

## 1.0.0 (2026-03-13)

### Features

* finalize uint quantization library with proofs and showcases ([2772350](https://github.com/0xferit/uint-quantization-lib/commit/2772350570f64f7cb4d7ed374e3134891dab031f))

### Bug Fixes

* update ShowcaseSolidityFixtures to use encode(value, true) instead of encodeLossless ([95a09e7](https://github.com/0xferit/uint-quantization-lib/commit/95a09e79c3ec9f29d81c04fb742b0c3204c61718))
