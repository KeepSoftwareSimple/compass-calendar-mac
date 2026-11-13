# Native workflows

## macOS workflows

Compass Desktop lives in `apps/calendar-macos`. Product context:
[Compass Desktop (macOS)](../features/desktop-client.md). Local setup:
[Compass for macOS](../development/local-development.md#compass-for-macos).

### macOS CI (`test-macos.yml`)

Source: [`.github/workflows/test-macos.yml`](../../.github/workflows/test-macos.yml)

- **Triggers:** pull requests and merge groups to `main`; manual
  `workflow_dispatch` (`strict_verify`). No push-to-`main` run.
- **Runner:** `macos-latest`.
- **Jobs:** `swift-packages` (`swift test` on CompassKit and CompassData,
  cached, no XcodeGen); `build` (`brew install xcodegen`, `xcodegen generate`,
  `xcodebuild test` for the app, `CompassKitTests`, and `CompassUITests`).
- **Required check:** rollup job `macos` (path-filtered on PRs; merge queue
  skips when the combined diff does not touch the Mac app).
- **App URL:** `COMPASS_APP_URL` defaults to staging for unauthenticated
  XCUITest smoke (`NativeLaunchTests` in anonymous demo mode).
- **Local:** `bun run verify` runs `test:macos:packages` and `test:macos` when
  Xcode is present; otherwise it reports both macOS legs as CI-only.

### Release macOS (`release-macos.yml`)

Source: [`.github/workflows/release-macos.yml`](../../.github/workflows/release-macos.yml)

- **Trigger:** push tag `macos-vX.Y.Z` or `macos-vX.Y.Z-rc.N` where `X.Y.Z`
  matches `MARKETING_VERSION` in `apps/calendar-macos/project.yml`.
- **Runner:** `macos-latest` (90-minute job timeout).
- **Secrets (required):** `CSC_LINK`, `CSC_KEY_PASSWORD`, `APPLE_API_KEY_P8`,
  `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_TEAM_ID`.
- **Pipeline:** render `icon.icns`, XcodeGen, universal Release archive with
  Developer ID signing and hardened runtime, `notarytool` submit and staple,
  `spctl --assess`, launch smoke (native window identifier), UDZO DMG attached to
  the GitHub Release for the tag.
- **Optional:** `SPARKLE_PRIVATE_KEY` when Sparkle appcast signing is enabled
  in the app (see tracking issue #4149).

Manual acceptance on a release DMG: [Desktop acceptance](../acceptance/desktop.md).

---
