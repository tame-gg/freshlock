//
//  main.swift
//  AppLockHelper
//
//  The AppLock background helper. This is a headless (accessory) process whose
//  sole job is to run the `LockEngine`: monitor launches, present overlays, and
//  drive Apple's native authentication. It runs independently of the settings
//  GUI — the GUI can quit and protection continues.
//
//  It shares the exact same on-disk configuration as the GUI
//  (`~/Library/Application Support/AppLock/configuration.json`) via
//  `FileSettingsService`, re-reading it on every event so the user's changes in
//  the GUI take effect immediately without any IPC.
//
//  Lifecycle: registered as a login-item agent by the GUI through
//  `SMAppService.agent(plistName:)`. See docs/ARCHITECTURE.md.
//

import AppKit
import AppLockCore
import AppLockEngine

/// The helper's application delegate: boots the engine once AppKit is ready.
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private var engine: LockEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)

            let settings = FileSettingsService()
            let engine = LockEngine(
                authService: LocalAuthenticationService(),
                unlockStore: UnlockStateStore(),
                configProvider: { (try? settings.load()) ?? .empty },
                configFileURL: settings.storeURL
            )
            engine.start()
            self.engine = engine

            Log.lifecycle.info("AppLock helper launched and protecting")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { engine?.stop() }
    }
}

// Standard AppKit bootstrap for a non-bundled/bundled executable.
let app = NSApplication.shared
let delegate = HelperAppDelegate()
app.delegate = delegate
app.run()
