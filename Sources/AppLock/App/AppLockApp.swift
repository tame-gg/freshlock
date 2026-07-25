//
//  AppLockApp.swift
//  AppLock
//
//  The SwiftUI entry point. AppLock is a menu-bar utility whose menu-bar item,
//  main window and About window are all managed in AppKit (StatusBarController,
//  WindowManager) so nothing pops up automatically at launch. The only SwiftUI
//  scene is `Settings`, which hosts Preferences and satisfies the requirement
//  that an `App` declare at least one scene.
//

import AppLockCore
import SwiftUI

/// The `UserDefaults`/`@AppStorage` key for menu-bar icon visibility, shared by
/// Preferences and the status-bar controller.
enum MenuBarPreference {
    static let key = "gg.tame.applock.showMenuBarIcon"
}

@main
struct AppLockApp: App {
    private let environment = AppEnvironment.shared

    /// Bootstraps the locking engine, the menu-bar item and window management.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(
                store: environment.configurationStore,
                loginItem: environment.helperLoginItem
            )
        }
    }
}
