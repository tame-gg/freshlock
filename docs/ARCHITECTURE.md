# Architecture

AppLock follows **MVVM** with strict dependency injection and a testable core.

## Module layout

```
Sources/
  AppLockCore/            # Pure, UI-free, fully unit-tested library
    Models/               # Value types: Configuration, ProtectedApp, …
    Services/             # AppDiscovery, Authentication, Settings persistence
    Managers/             # UnlockStateStore (pure lock-state machine)
    Utilities/            # os.Logger wrapper
  AppLockEngine/          # Shared AppKit locking engine (GUI + helper link it)
    LockEngine.swift      # Public composition root
    Services/             # AppMonitor, Overlay, Accessibility, LoginItem, …
    Managers/             # LockCoordinator, RelockManager
    Views/                # LockOverlayView + NSVisualEffect bridge
  AppLock/                # GUI executable (SwiftUI settings + menu bar)
    App/                  # @main, DI container, AppDelegate
    Managers/             # View models
    Views/                # Catalogue, preferences, about
  AppLockHelper/          # Headless background helper executable
    main.swift            # Boots a LockEngine and runs the loop
Tests/AppLockCoreTests/   # swift-testing unit tests
```

`AppLockCore` never imports AppKit/SwiftUI, which keeps the business logic
portable and trivially testable (`swift test`). `AppLockEngine` holds the
AppKit-dependent locking machinery and is linked by **both** the GUI and the
helper — that shared library is what makes "the helper does the protecting"
real rather than aspirational.

## Two processes, one configuration

```
┌────────────────────┐         configuration.json          ┌────────────────────┐
│   AppLock.app      │  writes  (App Support, atomic)  reads │  AppLockHelper.app │
│  (GUI / settings)  │ ───────────────────────────────────► │  (background)      │
│                    │                                       │   runs LockEngine  │
│  edits protected   │                                       │   monitors launches│
│  apps & settings   │                                       │   shows overlays   │
└────────────────────┘                                       └────────────────────┘
```

The two processes never talk directly — they coordinate purely through the
shared JSON document, which the helper re-reads on every event. The GUI can
quit and protection continues.

**Global shortcuts** live in whichever process runs the engine (`GlobalHotKeyService`,
Carbon `RegisterEventHotKey`). Because a shortcut edited in the GUI must reach the
helper, the engine also runs a `ConfigurationFileWatcher` (`DispatchSource`, no
polling) that re-registers the hot keys when the configuration file changes on
disk. This keeps cross-process edits live without any IPC.

**Registration & lifecycle.** The GUI registers the helper via
`SMAppService.agent(plistName: "gg.tame.applock.helper.plist")` when the user
enables *Launch at Login*. The helper is embedded at
`Contents/Library/LoginItems/AppLockHelper.app` with its launchd plist at
`Contents/Library/LaunchAgents/`, using `RunAtLoad` + `KeepAlive` so it starts
at login and is relaunched if it ever exits. When run from a bare SwiftPM binary
(no `.app`, hence no helper), the GUI detects the helper's absence and hosts the
`LockEngine` in-process so development still works.

## The lock/unlock flow

```
NSWorkspace launch/activate notification
        │
        ▼
  AppMonitorService  ──(Combine)──►  LockCoordinator
                                        │
                    protected & locked? │
                                        ▼
                              OverlayService  (top-most blur window per screen)
                                        │
                                        ▼
                     AuthenticationService  (Apple's native LA sheet)
                              success │ failure
                                ┌─────┴─────┐
                                ▼           ▼
                        UnlockStateStore   keep overlay /
                        grants unlock      terminate after N
                                ▼
                        OverlayService.dismiss
```

`RelockManager` observes sleep / screen-lock / session events and revokes the
matching grants in `UnlockStateStore`, driving auto-relock without any polling.

## Threat model & macOS limitations (honest)

AppLock is a **deterrent built on public APIs**, not a sandbox escape or a
kernel enforcement layer. Concretely:

| Goal | What macOS allows publicly | AppLock's approach |
|------|----------------------------|--------------------|
| Detect a launch | `NSWorkspace` notifications *after* launch begins | React on the notification, immediately overlay |
| Prevent a launch | ❌ No public pre-launch veto | Not possible; we cover + require auth instead |
| Freeze another app's UI | ❌ Not permitted | Top-most overlay intercepts interaction |
| Read another app's password | ❌ Never; nor do we want to | Use LocalAuthentication only |
| Guarantee no frame is drawn | ❌ Race between OS draw and our overlay | Overlay appears within a frame or two |

A sufficiently determined local user with admin rights can bypass any userland
app-locker (kill the process, boot to recovery, etc.). AppLock defends against
**casual/opportunistic access** to a logged-in Mac — the same practical threat
model as iOS app-lock features. This is stated plainly so users can make an
informed choice.

## Concurrency

The project builds under **Swift 6 language mode** with complete concurrency
checking. UI-facing services and stores are `@MainActor`-isolated; value models
are `Sendable`. Notification handlers extract `Sendable` fields before hopping to
the main actor to avoid data races.

## Persistence

The entire configuration is a single `Codable` `Configuration` document written
atomically to `~/Library/Application Support/AppLock/configuration.json`. This
one-document design makes export, backup, and future iCloud sync straightforward.

## Localization

AppLock ships English, Spanish and French. Add a language by translating
`Localization/en.lproj/Localizable.strings` — see [CONTRIBUTING.md](../CONTRIBUTING.md#localization).
