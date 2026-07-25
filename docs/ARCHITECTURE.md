# Architecture

FreshLock follows **MVVM** with strict dependency injection and a testable core.

## Module layout

```
Sources/
  FreshLockCore/            # Pure, UI-free, fully unit-tested library
    Models/               # Value types: Configuration, ProtectedApp, …
    Services/             # AppDiscovery, Authentication, Settings persistence
    Managers/             # UnlockStateStore (pure lock-state machine)
    Utilities/            # os.Logger wrapper
  FreshLockEngine/          # Shared AppKit locking engine (GUI + helper link it)
    LockEngine.swift      # Public composition root
    Services/             # AppMonitor, Accessibility, Overlay, LoginItem, …
    Managers/             # LockCoordinator, RelockManager
    Views/                # LockOverlayView + NSVisualEffect bridge
  FreshLockEnforce/         # Pure AUTH_EXEC policy (Phase 1; no ES link)
  FreshLockEnforceExtension/# ES client (package as .systemextension; not in default .app)
  FreshLock/                # GUI executable (SwiftUI settings + menu bar)
    App/                  # @main, DI container, AppDelegate
    Managers/             # View models
    Views/                # Catalogue, preferences, about
  FreshLockHelper/          # Headless background helper executable
    main.swift            # Boots a LockEngine and runs the loop
Tests/FreshLockCoreTests/   # swift-testing unit tests
```

`FreshLockCore` never imports AppKit/SwiftUI, which keeps the business logic
portable and trivially testable (`swift test`). `FreshLockEngine` holds the
AppKit-dependent locking machinery and is linked by **both** the GUI and the
helper — that shared library is what makes "the helper does the protecting"
real rather than aspirational. `FreshLockEnforce` holds pure exec-gate policy
for a future Endpoint Security path; see [THREAT_MODEL.md](THREAT_MODEL.md).

## Two processes, one configuration

```
┌────────────────────┐         configuration.json          ┌────────────────────┐
│   FreshLock.app      │  writes  (App Support, atomic)  reads │  FreshLockHelper.app │
│  (GUI / settings)  │ ───────────────────────────────────► │  (background)      │
│                    │                                       │   runs LockEngine  │
│  edits protected   │                                       │   monitors launches│
│  apps & settings   │                                       │   shows overlays   │
└────────────────────┘                                       └────────────────────┘
```

The two processes never talk directly; they coordinate purely through the
shared JSON document, which the helper re-reads on every event. Quitting the
GUI requires `deviceOwnerAuthentication` (Touch ID / Apple Watch / password)
via `applicationShouldTerminate`; cancel or failure aborts terminate so the
GUI and in-process engine keep running. After an authenticated GUI quit, the
helper (if registered as a login item) detects the GUI is gone and starts
its own `LockEngine`, so protection can continue without the settings UI.
Standalone/dev runs without a helper stop protecting when the GUI exits.

**Global shortcuts** live in whichever process runs the engine (`GlobalHotKeyService`,
Carbon `RegisterEventHotKey`). Because a shortcut edited in the GUI must reach the
helper, the engine also runs a `ConfigurationFileWatcher` (`DispatchSource`, no
polling) that re-registers the hot keys when the configuration file changes on
disk. This keeps cross-process edits live without any IPC.

**Registration & lifecycle.** The GUI registers the helper via
`SMAppService.agent(plistName: "gg.tame.freshlock.helper.plist")` when the user
enables *Launch at Login*. The helper is embedded at
`Contents/Library/LoginItems/FreshLockHelper.app` with its launchd plist at
`Contents/Library/LaunchAgents/`, using `RunAtLoad` + `KeepAlive` so it starts
at login and is relaunched if it ever exits. When run from a bare SwiftPM binary
(no `.app`, hence no helper), the GUI detects the helper's absence and hosts the
`LockEngine` in-process so development still works.

## The lock/unlock flow

```
NSWorkspace didLaunch / didActivate
        │
        ▼
  AppMonitorService  ──(Combine)──►  LockCoordinator
                                        │
                         beginSecuring (no frontmost gate)
                                        │
                         OverlayService  pin cover + wait for window
                         AccessibilityService (AX window events)
                                        │
                         (locked UI visible — do not activate FreshLock)
                                        │
                         AuthenticationService  (UIAgent focused LA sheet)
                              success │ failure
                                ┌─────┴─────┐
                                ▼           ▼
                        UnlockStateStore   keep overlay /
                        grant + dismiss    terminate after N
                        activate protected
```

`RelockManager` observes sleep / screen-lock / session events and revokes the
matching grants in `UnlockStateStore`. Grants with an inactivity scope are
checked on a light timer against real keyboard/mouse idle time. Together these
drive auto-relock without busy-polling.

### Why the host must not activate before Touch ID

FreshLock (and the helper) run as `.accessory` menu-bar processes. Calling
`NSApp.activate(ignoringOtherApps:)` on an accessory/LSUIElement host causes
macOS to **hide** the previously frontmost app — the protected app appears to
open and then vanish. LocalAuthentication presents its sheet through
`LocalAuthentication.UIAgent`, which takes focus for Touch ID without FreshLock
stealing activation. The pipeline is: reveal protected app → show lock overlay →
`evaluatePolicy` (focused system sheet on top).

### Application identity

Protected membership, overlays, unlock grants, and configuration are keyed by
**bundle identifier** — the only persistent identity that survives quit and
relaunch. Process IDs are session tokens only: an unlock grant records the
`sessionPID` that authenticated, and is valid solely for that live process.

Resolving "which process is this protected app?" never uses
`runningApplications(…).first` (undefined order). `ProtectedAppProcess` prefers
the frontmost instance of the bundle, otherwise the most recently launched.

### Unlock grants are process-scoped

A successful authentication creates an `UnlockGrant` keyed by bundle ID and
bound to that launch's **process ID**. `UnlockStateStore.revokeDeadSessions`
compares the grant's `sessionPID` against the set of live PIDs for that bundle
(poll + lifecycle events). Quit → relaunch therefore always requires a new
authentication. Queries (`isUnlocked`) never destroy grants on a PID mismatch —
only explicit lock / dead-session revocation / time expiry remove them.

Only one FreshLock process may own this state. A second copy of the app races
the first and produces intermittent unlock behaviour; launch activates the
existing instance and exits.

The Preferences option **Require authentication on every launch** additionally
forces a new prompt on every activation of a still-running process.

## Threat model & macOS limitations (honest)

**Authoritative write-up:** [THREAT_MODEL.md](THREAT_MODEL.md). Engineering plan for
stronger enforcement: [ENFORCEMENT.md](ENFORCEMENT.md).

FreshLock **today (Phase 0)** is a **userland deterrent**: overlays +
LocalAuthentication. That is **not** kernel enforcement. Do not describe overlays
as kernel-enforced.

| Goal | What macOS allows | FreshLock today (Phase 0) |
|------|-------------------|---------------------------|
| Detect a launch | `NSWorkspace` *after* launch begins | Cover immediately on notification |
| Detect windows | Accessibility (`AXObserver`) | Event-driven re-cover; CGWindowList fallback |
| Prevent a launch | Endpoint Security `AUTH_EXEC` (managed entitlement + sysext/root) | **Not shipping** — scaffolded in `FreshLockEnforce*`; overlays instead |
| Freeze another app's UI | Not permitted | Non-activating overlay intercepts interaction |
| Read another app's password | Never | LocalAuthentication only |
| Mission Control / Spaces / Exposé scrubbing | No public API to exclude another app's window | Overlay while covering; previews remain a limitation |
| Guarantee no frame is drawn | Overlay races OS draw | Cover within a frame or two via AX + overlay |
| "Admins cannot bypass" | Impossible for third-party on personally owned Macs | **Not claimed** — see THREAT_MODEL |

### Preview privacy (Mission Control, Spaces, Exposé, Stage Manager)

A covering overlay is a *separate* window, so system previews that snapshot the
protected app's own window can still show its contents when the app is locked
but not frontmost. Hiding the app would mitigate that, but it also cancels
LocalAuthentication when done around the Touch ID sheet. FreshLock prioritises a
stable authentication session (iOS-like) over Mission Control scrubbing.

### Accessibility permission

FreshLock **requires Accessibility** so it can observe window creation and geometry
for protected apps. Without it, covering falls back to `CGWindowList` polling and
is slower / less reliable. Grant it in System Settings → Privacy & Security →
Accessibility (also prompted during onboarding; status is shown in Preferences →
Advanced).

A local **admin** can bypass any third-party app locker (uninstall, revoke TCC,
Recovery, SIP off). FreshLock defends against **casual/opportunistic access** to
a logged-in Mac. Phase 1 ES scaffolding raises the bar to kernel-held exec deny
**if** Apple grants the entitlement; it still does not make admins unable to
remove the product.

## Concurrency

The project builds under **Swift 6 language mode** with complete concurrency
checking. UI-facing services and stores are `@MainActor`-isolated; value models
are `Sendable`. Notification handlers extract `Sendable` fields before hopping to
the main actor to avoid data races.

## Persistence

The entire configuration is a single `Codable` `Configuration` document written
atomically to `~/Library/Application Support/FreshLock/configuration.json`. This
one-document design makes export, backup, and future iCloud sync straightforward.

## Localization

FreshLock ships English, Spanish and French. Add a language by translating
`Localization/en.lproj/Localizable.strings` — see [CONTRIBUTING.md](../CONTRIBUTING.md#localization).
