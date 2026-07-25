//
//  AppDelegate.swift
//  FreshLock
//
//  A minimal `NSApplicationDelegate` used to bootstrap the background locking
//  engine at launch, keep FreshLock running as an accessory (menu bar) app with
//  no Dock icon, and present the first-launch onboarding guide.
//

import AppKit
import FreshLockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained for the lifetime of the app so onboarding can be replayed.
    private var onboarding: OnboardingPresenter?
    /// Owns the menu-bar status item.
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one FreshLock engine may own unlock state. A second copy
        // (e.g. "FreshLock 2.app") races the first and makes quit→relaunch
        // authentication intermittent.
        if Self.activateExistingInstanceIfNeeded() {
            NSApp.terminate(nil)
            return
        }

        // Accessory activation policy = menu-bar utility, no Dock icon. This is
        // the runtime equivalent of `LSUIElement` for an SPM-built binary and
        // is overridden by Info.plist when packaged as a proper .app.
        NSApp.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            let env = AppEnvironment.shared
            env.startServices()
            statusBar = StatusBarController(environment: env)

            let presenter = OnboardingPresenter(loginItem: env.helperLoginItem)
            onboarding = presenter
            presenter.presentIfNeeded()

            // Allow Preferences to replay the setup guide.
            NotificationCenter.default.addObserver(
                forName: OnboardingPresenter.replayNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { presenter.present() }
            }
        }
    }

    /// If another FreshLock process is already running, activate it and signal
    /// this process should exit. Returns `true` when this launch should abort.
    private static func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        guard let existing = others.first else { return false }
        existing.activate()
        return true
    }

    /// Reopening FreshLock (Finder/Spotlight/Dock). The window is never shown
    /// automatically at launch. On reopen we only surface it when the menu-bar
    /// icon is hidden — otherwise that would be the only way in. When the icon is
    /// visible, opening the app just activates it; use the menu bar to open the
    /// window, so it never pops up unexpectedly.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            let menuBarHidden = !UserDefaults.standard.bool(forKey: MenuBarPreference.key)
            if menuBarHidden {
                WindowManager.shared.showMain()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}
