## [8.0.0](https://github.com/0xferit/uint-quantization-lib/compare/v7.1.0...v8.0.0) (2026-11-20)

### Bug Fixes

* accept formatted release classifications ([ea70125](https://github.com/0xferit/uint-quantization-lib/commit/ea70125ff2b53ef61f6c35e64539247aab702fde))
* accept successful empty Soldeer revision lookups ([47dad63](https://github.com/0xferit/uint-quantization-lib/commit/47dad632ddd1b979a794f901a931475c8abd7398))
* atomically record release versions ([e488ca2](https://github.com/0xferit/uint-quantization-lib/commit/e488ca2311cbcd76914847640ac70907b890298e))
* compare equivalent showcase inputs and storage ([5ce1c1f](https://github.com/0xferit/uint-quantization-lib/commit/5ce1c1f8c1909903b24f2f2192acf23f1edbf342))
* enforce staking showcase lifecycle ([4e0ad94](https://github.com/0xferit/uint-quantization-lib/commit/4e0ad94415fbc837604e72d0088bba1dfa119380))
* keep the documented install version in sync ([cefc7a2](https://github.com/0xferit/uint-quantization-lib/commit/cefc7a2219721b1be3489c9aa31c298505ac2955))
* log rejected release classifier replies ([fc6c725](https://github.com/0xferit/uint-quantization-lib/commit/fc6c725830ccba642f0627b49596be4bd676d7c0))
* match literal dots in stable release tags ([17e857c](https://github.com/0xferit/uint-quantization-lib/commit/17e857cf29656e1becb60a6290aec2f3eb1763e3))
* use custom errors for staking lifecycle checks ([eb750a4](https://github.com/0xferit/uint-quantization-lib/commit/eb750a4068d5adf6263b0e4aded609d2e49fee4a))
* validate planner schemes against the domain cap ([9d2e0b8](https://github.com/0xferit/uint-quantization-lib/commit/9d2e0b8519178fa790e8f9477a142b01d54ce15b))

## [7.1.0](https://github.com/0xferit/uint-quantization-lib/compare/v7.0.1...v7.1.0) (2026-03-14)

### Features

* add requireAligned() and requireMinStep() convenience guards ([0acead9](https://github.com/0xferit/uint-quantization-lib/commit/0acead9b4ed00e1f1265f94b8d0107cd1a04efa7))

### Bug Fixes

* badge now measures strict path and parses test logs ([9413c86](https://github.com/0xferit/uint-quantization-lib/commit/9413c868687fc2ee8246fe507359ebbc646ac96f))

## [7.0.1](https://github.com/0xferit/uint-quantization-lib/compare/v7.0.0...v7.0.1) (2026-03-13)

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
