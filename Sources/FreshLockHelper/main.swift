//
//  main.swift
//  FreshLockHelper
//
//  The FreshLock background helper. Its job is to run the `LockEngine` when the
//  settings GUI is *not* running — protecting apps after the GUI quits and
//  before it launches at login. When the GUI is running it is authoritative, so
//  the helper stands down to guarantee the two never run two engines at once.
//
//  It shares the exact same on-disk configuration as the GUI
//  (`~/Library/Application Support/FreshLock/configuration.json`) via
//  `FileSettingsService`, re-reading it on every event so the user's changes in
//  the GUI take effect immediately without any IPC.
//
//  Lifecycle: registered as a login-item agent by the GUI through
//  `SMAppService.agent(plistName:)`. See docs/ARCHITECTURE.md.
//

import AppKit
import FreshLockCore
import FreshLockEngine

/// The helper's application delegate. `NSApplicationDelegate` is `@MainActor` in
/// the SDK, so the whole delegate is main-actor isolated.
@MainActor
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private static let mainAppBundleID = "gg.tame.freshlock"

    private let settings = FileSettingsService()
    private var engine: LockEngine?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        observeMainApp()
        reconcile()
        Log.lifecycle.info("FreshLock helper launched")
    }

    /// Start the engine when the GUI isn't running; stop it when the GUI appears.
    private func reconcile() {
        let guiRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.mainAppBundleID).isEmpty

        if guiRunning {
            if engine != nil {
                engine?.stop()
                engine = nil
                Log.lifecycle.info("Helper standing down; GUI is running")
            }
        } else if engine == nil {
            let engine = LockEngine(
                authService: LocalAuthenticationService(),
                unlockStore: UnlockStateStore(),
                configProvider: { [settings] in (try? settings.load()) ?? .empty },
                configFileURL: settings.storeURL
            )
            engine.start()
            self.engine = engine
            Log.lifecycle.info("Helper protecting; GUI is not running")
        }
    }

    private func observeMainApp() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            })
        }
    }

    func applicationWillTerminate(_: Notification) {
        engine?.stop()
    }
}

// AppKit bootstrap. Top-level code in an executable's main.swift is main-actor
// isolated, so constructing the @MainActor delegate here is safe.
let app = NSApplication.shared
let delegate = HelperAppDelegate()
app.delegate = delegate
app.run()
