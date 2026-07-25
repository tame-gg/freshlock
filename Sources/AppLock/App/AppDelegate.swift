//
//  AppDelegate.swift
//  AppLock
//
//  A minimal `NSApplicationDelegate` used to bootstrap the background locking
//  engine at launch, keep AppLock running as an accessory (menu bar) app with
//  no Dock icon, and present the first-launch onboarding guide.
//

import AppKit
import AppLockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained for the lifetime of the app so onboarding can be replayed.
    private var onboarding: OnboardingPresenter?
    /// Owns the menu-bar status item.
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory activation policy = menu-bar utility, no Dock icon. This is
        // the runtime equivalent of `LSUIElement` for an SPM-built binary and
        // is overridden by Info.plist when packaged as a proper .app.
        NSApp.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            let env = AppEnvironment.shared
            env.startServices()
            statusBar = StatusBarController(environment: env)

            let presenter = OnboardingPresenter(
                accessibility: env.accessibility,
                loginItem: env.helperLoginItem
            )
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

    /// Reopening AppLock (Finder/Spotlight/Dock) surfaces the main window — the
    /// way back when the menu-bar icon is hidden. The window is otherwise never
    /// shown automatically, so launching at login stays silent.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { WindowManager.shared.showMain() }
        return true
    }
}
