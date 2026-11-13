# Compass for macOS

Native Compass app, Swift packages, UI tests, release tooling, and parity accounting.
The web app and services live in [compass-calendar](https://github.com/KeepSoftwareSimple/compass-calendar).

The existing apps/calendar-macos layout is preserved so Xcode and test paths stay stable.

## Build and test

Install Xcode and XcodeGen (`brew install xcodegen`), then:

```sh
bash .github/scripts/render-macos-icon.sh
bun test:contracts
bun run test
```

Open the generated apps/calendar-macos/Compass.xcodeproj for development.
Native PR checks run here, independently of web CI. Strict native verification is available with
`gh workflow run test-macos.yml -f strict_verify=true`.

## Update shared contracts and fixtures

```sh
bash .github/scripts/sync-from-web.sh /absolute/path/to/compass-calendar
COMPASS_WEB_SOURCE=/absolute/path/to/compass-calendar bun test:source-contracts
```

The source checkout must have `bun install` completed and a clean working tree. This records its commit in
WEB_SOURCE_REVISION and refreshes committed generated files. Review and commit both together.
Ordinary native builds use the committed artifacts and need no source-repo checkout or token.

## Repository setup after extraction

- Require the `macos` check here for native builds. The source repo retains that required name as a small Ubuntu boundary check, so organization settings need no change.
- An owner must configure Apple signing/notarization and Sparkle secrets here before releasing. See the release workflows for names.
- Release build numbers use Unix timestamps so the new repository run counter cannot downgrade Sparkle versions.
- Update feeds embedded in this source now point here. Existing installations still use the old repository feed;
  an owner must publish a signed bridge update on that feed before retiring it. Preserve old release assets.
- Manual web parity screenshots require COMPASS_SOURCE_TOKEN with read access to the private source repository.
  COMPASS_WEB_REF selects the source ref (defaults to main). Native CI does not need this token.
- The parity worker is disabled by default. Its parent issue, source watermark, credentials, and repository variables
  must be re-established before enabling MACOS_PARITY_LOOP_ENABLED. Imported issue numbers are historical source references.

See [import provenance](SOURCE.md) and [desktop documentation](docs/features/desktop-client.md).
