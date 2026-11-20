# Architecture

## Quantization library

[`src/UintQuantizationLib.sol`](src/UintQuantizationLib.sol) defines the `Quant` scheme and its pure operations. The scheme stores both bit widths in one value. The library validates the widths when callers construct a scheme. The checked encoders and decoders validate their inputs against that scheme. Contracts can reuse a scheme as an immutable value.

## Benchmark fixtures

[`src/showcase/ShowcaseSolidityFixtures.sol`](src/showcase/ShowcaseSolidityFixtures.sol) holds two pairs of fixtures for measuring storage costs. The staking pair records each account's amount, timestamps and active flag. Each account can hold one active stake until it withdraws. Withdrawal becomes available at the one-day deadline. The quantized fixture stores the encoded amount and repays its decoded value. Strict deposits preserve the full amount. Floor deposits leave any discarded remainder in the fixture, including the entire deposit when it is smaller than one step.

The extreme packing pair compares a fixed array of full-width values with quantized values packed into one slot. The tests in [`test/showcase/`](test/showcase/) measure first-write costs and exercise the staking lifecycle.

The staking benchmark also compares an exact packed amount with the quantized fixture's deposit ceiling. That baseline isolates the effect of the amount representation when either record fits in one slot. On main, a read-only job measures gas and passes the numbers to a separate job that publishes the README badges on the `gh-badges` branch.

## Documentation site

[`index.html`](index.html) links to installation instructions and shows a worked example. [`playground.html`](playground.html) renders planner inputs and results. The page and the Node.js regression tests use [`planner.js`](planner.js) to validate the cap and shift and derive a scheme that covers the input domain.

## Release and validation

Every pull request audits the locked release dependencies for high and critical npm advisories. Release preparation installs the locked tools, verifies their signatures and repeats the audit with current advisory data.

The release workflow calls the same read-only validation workflow used by pull requests. The version classifier sees the Solidity diff and must return a valid semantic version bump before semantic-release can prepare a release. Semantic-release validates the generated versioned source before atomically pushing the release commit and version tag.

A tagged release remains pending until the Soldeer registry serves its Solidity source. Release runs are serialized and recover the pending tag before preparing another version. Registry verification compares the published Solidity files with the selected tag before moving the publication marker. A manual backfill selects an existing version tag on main and leaves a newer marker and GitHub Latest release in place.
