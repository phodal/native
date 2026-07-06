# Agent Rules

## Releasing

Releases are manual, single-PR affairs. The maintainer controls the changelog voice and format.

To prepare a release:

1. Create a branch (e.g. `prepare-v1.2.0`)
2. Bump the version in `packages/native-sdk/package.json`
3. Run `npm --prefix packages/native-sdk run version:sync` to update all version references
4. Write the changelog entry in `CHANGELOG.md`, wrapped in `<!-- release:start -->` and `<!-- release:end -->` markers
5. Remove the `<!-- release:start -->` and `<!-- release:end -->` markers from the previous release entry; only the latest release should have markers
6. Open a PR and merge to `main`

CI compares the version in `packages/native-sdk/package.json` to what's on npm. If it differs, it cross-builds the CLI for every platform, creates the GitHub release with the binaries, publishes the per-platform binary packages (`packages/native-sdk/npm/*`), and publishes `@native-sdk/cli` last — so the main package only lands once every binary package it pins is live. If npm already has the version but the GitHub release is missing assets, CI recreates the GitHub release from the marked changelog entry.

Publishing requires the `NPM_TOKEN` secret (an npm automation token with publish rights on the `@native-sdk` scope) in the repository's `Release` environment; the workflow fails loudly before touching the registry when it is missing.
