# Building FreshLock

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

# Assemble a runnable FreshLock.app (release, universal by default)
Scripts/build-app.sh
open dist/FreshLock.app

# Or produce a full release artifact (signed .app + zip + SHA256)
Scripts/package-release.sh
open dist/FreshLock.app
```

`Scripts/build-app.sh` accepts an output directory and honours these environment
variables:

| Variable | Values | Default |
|----------|--------|---------|
| `CONFIGURATION` | `debug`, `release` | `release` |
| `ARCH` | `arm64`, `x86_64`, `universal` | `universal` |
| `EMBED_SYSTEM_EXTENSION` | `0`, `1` | `0` |

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
Scripts/sign-and-notarize.sh dist/FreshLock.app
```

If the signing variables are unset, the script prints a notice and exits
successfully, producing an **unsigned** build (Gatekeeper will warn on first
launch). CI relies on this graceful-skip behaviour.

## Opening in Xcode

Swift Package Manager packages open directly:

```bash
xed .
```

Xcode will resolve the package and let you build/run the `FreshLock` scheme.

## Phase 1 enforcement targets (scaffolding)

```bash
# Pure policy library + unit tests (no entitlement)
swift build --product FreshLockEnforce
swift test

# ES client binary (links libEndpointSecurity; exits cleanly if not entitled)
swift build --product FreshLockEnforceExtension

# Assemble gg.tame.freshlock.enforce.systemextension
Scripts/build-systemextension.sh

# Optional: embed sysext into FreshLock.app (off by default)
EMBED_SYSTEM_EXTENSION=1 Scripts/build-app.sh
```

Default `Scripts/build-app.sh` does **not** embed the system extension, so Phase 0
users without Apple's ES entitlement keep a normal shipping build.

`FreshLockEnforceExtension` exits 0 when entitlement / privilege / FDA are unmet.
Host registration UI: Preferences → Advanced → Developer mode → Activate system
extension. See [ENFORCEMENT.md](ENFORCEMENT.md) and [THREAT_MODEL.md](THREAT_MODEL.md).

## Why a script instead of an `.xcodeproj`?

The core logic lives in an SPM package so `swift test` runs anywhere (including
CI) with no project file to drift out of sync. `Scripts/build-app.sh` wraps the
SPM binary into a proper `.app` bundle for distribution. See
[ARCHITECTURE.md](ARCHITECTURE.md).
