# Native local development


## Compass for macOS

Source: [`apps/calendar-macos`](../../apps/calendar-macos). Feature decisions and
architecture: [Compass Desktop (macOS)](../features/desktop-client.md).

The Mac app is a fully native Swift UI. Linux agents and Cursor Cloud VMs
cannot compile AppKit; macOS builds and tests run on GitHub `macos-latest`
([macOS workflow](../CI-CD/workflows.md#macos-workflows)).

Shared contracts and shortcuts come from TypeScript generators (run on Linux
before you push Swift changes):

```bash
bash .github/scripts/sync-from-web.sh /absolute/path/to/compass-calendar
```

Run the sync script with a clean source checkout when updating Zod schemas, shortcuts, theme
tokens, or parity fixtures. It generates and checks the native artifacts and records the source revision.

### Prerequisites

- macOS 14 Sonoma or newer (matches the native app floor in the desktop spec)
- Xcode from the Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/)
- XcodeGen: `brew install xcodegen`

### Generate and open the project

```bash
cd apps/calendar-macos
xcodegen generate
open Compass.xcodeproj
```

Select the **Compass** scheme in Xcode and run (⌘R). The calendar UI is
native; API calls use `AppHostPreference` (production by default).

### API host (production vs staging)

`AppHostPreference` in CompassKit selects which Compass origin backs
`/api/*` and SSE. Release builds default to production.

For local QA against staging or a tunneled backend:

1. **Debug menu (recommended):** Hold **Option** while launching Compass, or
   use a dev-channel DMG, then **Debug → Switch to Staging** or **Switch to
   Production** (persists in `UserDefaults`; see
   [Desktop acceptance](../acceptance/desktop.md)).
2. **Launch override:** `-COMPASS_APP_URL` with an `https://` origin (for
   example `https://staging.compasscalendar.com`). Same key as
   `Resources/Info.plist` when no saved preference exists.

Do not commit a non-production URL in `Info.plist` unless the team explicitly
wants that default for everyone.

### Debug menu

The **Debug** menu appears when any of these is true: **Option** held at
launch, `COMPASS_UPDATE_CHANNEL=dev`, `COMPASS_INTERNAL=1`, `#if DEBUG`
builds, or the `COMPASS_INTERNAL` Info.plist flag. It exposes theme toggles,
**Open Quick Add Panel** (for XCUITest and manual panel checks), and staging
host switches. Release DMGs without those flags hide the menu.

### Shell commands for Debug builds

Debug builds (`#if DEBUG`, so never a Release DMG) accept `compass://debug/...`
links that run the same model paths as the keyboard, without activating the
app. Pass the build with `-a` so the link reaches it and not another installed
Compass, and `-g` to keep it in the background:

```bash
APP=apps/calendar-macos/build/DerivedData/Build/Products/Debug/Compass.app
open -g -a "$APP" "compass://debug/create?title=Standup&start=2026-10-16T09:30&minutes=30"
open -g -a "$APP" "compass://debug/undo"
```

| Command | Effect |
|---|---|
| `create?title=…[&start=yyyy-MM-ddTHH:mm][&minutes=60]` | Saves a timed event on the default calendar. Without `start` it uses the next keyboard-create slot. |
| `delete?id=…` | Deletes one event (`scope: this`). |
| `undo`, `redo` | Same as Edit → Undo / Redo. |
| `today`, `goto?date=yyyy-MM-dd` | Moves the grid. |
| `view/day`, `view/week`, `view/life` | Switches the view. |

Commands sent during a cold launch wait until the calendar model has started.
Check results without the UI: in local mode, events live in
`~/Library/Application Support/Compass/compass.sqlite` (`local_event`).
Commands record shortcut usage like the keys they mirror.

### Unsigned local builds

`project.yml` uses ad hoc signing (`CODE_SIGN_IDENTITY: "-"`). Xcode builds
are not notarized. Gatekeeper may refuse the first launch from Finder;
right-click the app → **Open**, or run from Xcode (DerivedData).

Notifications, OAuth relay edge cases, and auto-update flows are validated
on signed CI DMGs installed to `/Applications`. Use a GitHub Release asset
from a `macos-v*` tag for acceptance runs.

### Command-line tests

Pure SwiftPM packages (`CompassKit`, `CompassData`) run without XcodeGen:

```bash
swift test --package-path apps/calendar-macos/CompassKit
swift test --package-path apps/calendar-macos/CompassData
```

Or from the repo root: `bun run test:macos:packages`.

The app target, `CompassUI`, and XCUITest still go through XcodeGen and
`xcodebuild test`:

```bash
cd apps/calendar-macos
xcodegen generate
xcodebuild test -project Compass.xcodeproj -scheme Compass \
  -destination 'platform=macOS'
```

Local XCUITest uses the shared desktop. Run it only when the Mac is unlocked,
the user is not using it, and no other native UI or strict verification run is
active. Otherwise run the full gate on an isolated CI Mac:
`gh workflow run test-macos.yml --ref <branch> -f strict_verify=true`.
This runs `bun run verify --strict` and preserves its log without using the
local desktop. Inspect the `strict` job verdict before marking a PR ready. The shared test
application activates Compass after launch, before hit testing. XCTest may
otherwise treat another app covering Compass as an interruption and inspect
that app; this triggered a Brave crash inside an XCTest predicate query. If
that happens, stop the run rather than repeatedly inspecting the other app.
Do not dismiss user dialogs or change system security settings to make tests pass.

`CompassUITests` launch with `-COMPASS_FIXTURE demo` for anonymous smoke (no
backend) and `-COMPASS_UI_TEST` (via `XCUIApplication.compassUITest()`), which
attaches the AppKit accessibility probes the tests read. Launches without it
attach no probes, so they cannot steal keyboard focus in shipped builds. CI
runs pure packages in the `swift-packages` job and the app in the `build` job;
see
[test-macos.yml](../../.github/workflows/test-macos.yml).

## Common Failure Modes

- backend exits immediately because required YAML config is missing
- backend/web/cli read from `compass.yaml` at the repo root; using `.env` no longer configures Compass
- web points at the wrong API base URL
- session exists but user profile fetch fails
- sync endpoints work but notification/watch setup is skipped because neither `google.webhookUrl` nor `backend.apiUrl` is public HTTPS
- `google.webhookUrl` points to a tunnel without `/api`, so Google posts to the wrong route
- backend starts but `/api/health` returns `500` because `mongo.uri` or database reachability is broken
