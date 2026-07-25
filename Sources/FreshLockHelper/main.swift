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
    ///
    /// Any FreshLock-family GUI counts, not just the shipping bundle ID. Two
    /// engines enforcing the same app is catastrophic rather than merely
    /// redundant: each holds its own unlock state, each covers the app, and each
    /// activates itself to raise a Touch ID sheet - which the other reads as the
    /// user switching apps, so both cancel and re-prompt in a loop that leaves
    /// nothing on screen clickable. A dev or preview build with a suffixed
    /// identifier used to slip past an exact-match check.
    private func reconcile() {
        let ownID = Bundle.main.bundleIdentifier
        let guiRunning = NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier, id != ownID, !id.hasSuffix(".helper") else { return false }
            return id == Self.mainAppBundleID || id.hasPrefix(Self.mainAppBundleID + ".")
        }

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
