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
  AppLock/                # Executable app target (AppKit + SwiftUI)
    App/                  # @main, DI container, AppDelegate
    Services/             # AppMonitor, Overlay, Accessibility, LoginItem, …
    Managers/             # LockCoordinator, RelockManager, view models
    Views/                # SwiftUI views + NSVisualEffect bridge
Tests/AppLockCoreTests/   # swift-testing unit tests
```

`AppLockCore` never imports AppKit/SwiftUI, which keeps the business logic
portable and trivially testable (`swift test`). The app target depends on the
core; a future background helper can link the same core without the UI.

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
