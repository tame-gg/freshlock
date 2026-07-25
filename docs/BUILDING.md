# Building AppLock

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 17+ / Swift 6 toolchain
- Command Line Tools (`xcode-select --install`)

## Build & run

```bash
# Compile everything
swift build

# Run the unit tests
swift test

# Assemble a runnable AppLock.app (release, universal by default)
Scripts/build-app.sh
open dist/AppLock.app
```

`Scripts/build-app.sh` accepts an output directory and honours two environment
variables:

| Variable        | Values                     | Default     |
|-----------------|----------------------------|-------------|
| `CONFIGURATION` | `debug`, `release`         | `release`   |
| `ARCH`          | `arm64`, `x86_64`, `universal` | `universal` |

```bash
CONFIGURATION=debug ARCH=arm64 Scripts/build-app.sh build/
```

## Signing & notarization

Distribution builds should be signed with a Developer ID and notarized:

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="app-specific-password"

Scripts/build-app.sh
Scripts/sign-and-notarize.sh dist/AppLock.app
```

If the signing variables are unset, the script prints a notice and exits
successfully, producing an **unsigned** build (Gatekeeper will warn on first
launch). CI relies on this graceful-skip behaviour.

## Opening in Xcode

Swift Package Manager packages open directly:

```bash
xed .
```

Xcode will resolve the package and let you build/run the `AppLock` scheme.

## Why a script instead of an `.xcodeproj`?

The core logic lives in an SPM package so `swift test` runs anywhere (including
CI) with no project file to drift out of sync. `Scripts/build-app.sh` wraps the
SPM binary into a proper `.app` bundle for distribution. See
[ARCHITECTURE.md](ARCHITECTURE.md).
