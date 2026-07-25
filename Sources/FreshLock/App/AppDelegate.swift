//
//  AppDelegate.swift
//  FreshLock
//
//  A minimal `NSApplicationDelegate` used to bootstrap the background locking
//  engine at launch, keep FreshLock running as an accessory (menu bar) app with
//  no Dock icon, and present the first-launch onboarding guide.
//
//  Quit is gated by LocalAuthentication (`deviceOwnerAuthentication`): ⌘Q,
//  menu Quit, and status-bar Quit all hit `applicationShouldTerminate`. Closing
//  windows does not quit. Incomplete first-run onboarding is the exception -
//  Quit / ⌘Q terminate without LA so the non-closable setup window is escapable.
//  After an authenticated GUI quit, the login-item helper
//  (if registered) starts its own LockEngine so protection can continue without
//  the settings UI; standalone/dev runs with only the in-process engine stop
//  protecting when the GUI exits.
//

import AppKit
import FreshLockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained for the lifetime of the app so onboarding can be replayed.
    private var onboarding: OnboardingPresenter?
    /// Owns the menu-bar status item.
    private var statusBar: StatusBarController?

    /// Skip quit auth for the duplicate-instance handoff only (second copy exits
    /// immediately after activating the already-running FreshLock).
    private var allowTerminateWithoutAuth = false
    /// True while a quit LocalAuthentication prompt is in flight.
    private var isAuthenticatingQuit = false

    func applicationDidFinishLaunching(_: Notification) {
        // Only one FreshLock engine may own unlock state. A second copy
        // (e.g. "FreshLock 2.app") races the first and makes quit→relaunch
        // authentication intermittent.
        if Self.activateExistingInstanceIfNeeded() {
            allowTerminateWithoutAuth = true
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

    /// Closing the last window must not quit - FreshLock is a menu-bar utility.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// Central quit gate: every `NSApp.terminate` path (⌘Q, app menu Quit,
    /// status-bar Quit) prompts for device-owner authentication first.
    /// Incomplete first-run onboarding skips LA so the non-closable setup window
    /// has a real exit path (Quit / ⌘Q) before protection is configured.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if allowTerminateWithoutAuth {
            return .terminateNow
        }
        if onboarding?.hasCompletedOnboarding == false {
            Log.lifecycle.info("Quit during incomplete onboarding; terminating without auth")
            return .terminateNow
        }
        if isAuthenticatingQuit {
            return .terminateCancel
        }

        isAuthenticatingQuit = true
        Task { @MainActor in
            // Dismiss any in-flight unlock prompt so quit auth owns the sheet.
            let auth = AppEnvironment.shared.authService
            auth.cancel()
            NSApp.activate(ignoringOtherApps: true)
            await Task.yield()

            let result = await auth.authenticate(
                reason: "quit FreshLock and stop protecting apps"
            )
            let allow: Bool
            switch result {
            case .success:
                allow = true
                Log.lifecycle.info("Quit authenticated; terminating GUI")
            case .cancelled:
                allow = false
                Log.lifecycle.info("Quit cancelled; staying alive")
            case .failure:
                allow = false
                Log.lifecycle.notice("Quit authentication failed; staying alive")
            }
            isAuthenticatingQuit = false
            NSApp.reply(toApplicationShouldTerminate: allow)
        }
        return .terminateLater
    }

    /// Reopening FreshLock (Finder/Spotlight/Dock). The window is never shown
    /// automatically at launch. On reopen we only surface it when the menu-bar
    /// icon is hidden — otherwise that would be the only way in. When the icon is
    /// visible, opening the app just activates it; use the menu bar to open the
    /// window, so it never pops up unexpectedly.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
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
