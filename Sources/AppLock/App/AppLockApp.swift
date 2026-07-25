//
//  AppLockApp.swift
//  AppLock
//
//  The SwiftUI entry point. AppLock is a menu-bar utility whose menu-bar item,
//  main window, Preferences and About window are all managed in AppKit
//  (StatusBarController, WindowManager) so nothing pops up automatically at
//  launch and they open reliably from code.
//

import SwiftUI

/// The `UserDefaults`/`@AppStorage` key for menu-bar icon visibility, shared by
/// Preferences and the status-bar controller.
enum MenuBarPreference {
    static let key = "gg.tame.applock.showMenuBarIcon"
}

@main
struct AppLockApp: App {
    /// Bootstraps the locking engine, the menu-bar item and window management.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A SwiftUI `App` must declare at least one scene, but AppLock's real
        // windows (main, Preferences, About) are AppKit-hosted by WindowManager
        // so they never appear at launch and open reliably from code. This
        // hidden, suppressed window satisfies the requirement without ever
        // showing anything.
        Window("AppLock", id: "root") { EmptyView() }
            .defaultLaunchBehavior(.suppressed)
    }
}
