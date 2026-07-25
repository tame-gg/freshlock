# Codebase Onboarding

FreshLock is a native **macOS 15+** menu-bar utility that locks apps behind Touch ID / Apple Watch / password. It is a **Swift 6 SPM** app (not a web monorepo): four modules, MVVM, and a shared JSON config between GUI and helper processes.

## Quick Start

1. Clone the repo (requires macOS 15+, Xcode 17+ / Swift 6)
2. Install dependencies: none — SPM with no third-party packages (`swift build` resolves)
3. Set up environment: none — no `.env`; config lives at `~/Library/Application Support/FreshLock/configuration.json`
4. Run tests: `swift test`
5. Build and run:
   ```bash
   Scripts/build-app.sh
   open dist/FreshLock.app
   ```
   Or open in Xcode: `xed .`

Optional lint tooling: `brew install swiftlint swiftformat`

**Gotchas:** bare `swift build` / `swift run` skips `.app` packaging (no localizations, no embedded helper). Prefer `Scripts/build-app.sh`. Grant **Accessibility** on first run. Launch at Login expects the app under `/Applications`.

## Architecture

Two-process native desktop app coordinated via a shared config file — no IPC, no network API.

| Layer | Choice |
|--------|--------|
| Language | Swift 6 (strict concurrency) |
| Build | Swift Package Manager (`Package.swift`) |
| UI | SwiftUI views in AppKit windows; menu-bar first (`LSUIElement`) |
| Auth | Apple LocalAuthentication |
| Persistence | Atomic JSON under Application Support |
| Tests | Swift Testing (`FreshLockCoreTests`) |
| Distribution | GitHub Releases + Homebrew cask; Developer ID + notarization |

### Modules

| Target | Role |
|--------|------|
| **FreshLockCore** | UI-free models/services (unit-tested). No AppKit/SwiftUI. |
| **FreshLockEngine** | Shared locking engine: monitor → overlay → auth → unlock/relock |
| **FreshLock** | GUI executable: menu bar, catalogue, preferences, onboarding |
| **FreshLockHelper** | Headless helper; runs engine when GUI is quit |

```
┌─────────────────────┐     configuration.json      ┌──────────────────────┐
│  FreshLock.app      │  writes (atomic)            │  FreshLockHelper.app │
│  GUI / settings     │ ──────────────────────────► │  background agent    │
│  (+ engine while    │  helper re-reads on events  │  runs LockEngine     │
│   GUI is running)   │  file watcher for shortcuts │  when GUI is quit    │
└─────────────────────┘                             └──────────────────────┘
```

While the GUI runs it hosts the engine; the helper stands down so only one engine owns unlock state.

### Lock flow

`NSWorkspace` launch/activate → `AppMonitorService` → `LockCoordinator` → overlay + Accessibility → `LocalAuthentication` → `UnlockStateStore` grant (bundle ID + session PID).

Threat model: userland deterrent on public APIs — not kernel enforcement. Intentionally unsandboxed.

## Data Models

No traditional database or ORM. Persistence is Codable JSON + a few UserDefaults keys.

**Root document** (`Configuration`, `schemaVersion: 1`):

- `settings: AppSettings` — launch at login, grace period, default relock, overlay style, shortcuts, etc.
- `protectedApps: [ProtectedApp]` — keyed by `bundleIdentifier`; enabled/favorite, category, optional relock override, optional `terminateAfterFailures`

**Runtime only (not persisted):**

- `UnlockGrant` / `UnlockScope` — in-memory, PID-scoped; lost on process exit

**Discovered, not stored as config:**

- `InstalledApp` — scanned from Applications directories

**UserDefaults:** `showMenuBarIcon`, `hasCompletedOnboarding`

Migrations: document `schemaVersion` only; reject newer schemas; no upgrade path from older versions yet.

## API Reference

There is **no HTTP/REST/GraphQL/tRPC API**. Integration surface:

1. **Config file** — `~/Library/Application Support/FreshLock/configuration.json` (GUI writes; helper/engine re-reads)
2. **Swift service protocols** — `SettingsServiceProtocol`, `AuthenticationServiceProtocol`, `AppDiscoveryServiceProtocol`, `LoginItemServiceProtocol`, `LockEngine`
3. **OS events** — `NSWorkspace` launch/activate/terminate/sleep, screen lock distributed notification, Accessibility `AXObserver`, Carbon hot keys, `SMAppService` launchd agent

Import/export uses the same JSON schema via Preferences.

## Authentication

Not a cloud/SaaS auth stack. Device-owner proof via **LocalAuthentication** (`deviceOwnerAuthentication`): Touch ID, Apple Watch, or Mac password. FreshLock never sees or stores credentials.

- Unlock “session” = in-memory `UnlockGrant` bound to `sessionPID`
- Quit → new PID → must re-auth
- No roles, orgs, OAuth, or deep links
- Relock policies: every launch, after minutes, sleep, screen lock, inactivity, switching away, manual only (default: after switching away)

**Nuance:** menu-bar “Unlock Until Sleep/Logout” writes grants without LocalAuthentication; the Unlock All hotkey does require LA.

## Deployment

| Target | Status |
|--------|--------|
| GitHub Releases | Tag `v*.*.*` → zip + SHA256 |
| Homebrew cask | `brew tap tame-gg/tap && brew install --cask freshlock` |
| App Store / Docker / Vercel | Not applicable (unsandboxed native app) |

**CI** (`.github/workflows/ci.yml` on `macos-15`): build, `swift test --parallel`, SwiftLint strict, SwiftFormat lint, package `.app` artifact.

**Release secrets** (optional): `SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `HOMEBREW_TAP_TOKEN`. Without them: ad-hoc zip still publishes; cask bump skipped.

## Key Files to Know

- `docs/ARCHITECTURE.md` — module layout, two-process model, lock flow, threat model
- `Package.swift` — target graph (Core → Engine → GUI / Helper)
- `Sources/FreshLock/App/FreshLockApp.swift` — `@main` SwiftUI entry
- `Sources/FreshLock/App/AppDelegate.swift` — bootstrap, single-instance, menu bar
- `Sources/FreshLock/App/AppEnvironment.swift` — DI + in-process vs helper engine hosting
- `Sources/FreshLockEngine/LockEngine.swift` — engine composition root
- `Sources/FreshLockEngine/Managers/LockCoordinator.swift` — overlay → auth → grant
- `Sources/FreshLockHelper/main.swift` — helper lifecycle
- `Sources/FreshLockCore/Models/Configuration.swift` — persistence contract
- `Sources/FreshLockCore/Services/SettingsService.swift` — atomic JSON I/O
- `Scripts/build-app.sh` — SPM → runnable `.app`
- `docs/BUILDING.md` / `docs/RELEASING.md` — build and release runbooks
