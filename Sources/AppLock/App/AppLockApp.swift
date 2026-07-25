//
//  AppLockApp.swift
//  AppLock
//
//  The SwiftUI entry point. AppLock is primarily a menu-bar (`LSUIElement`)
//  utility: a `MenuBarExtra` scene is always present, and a conventional
//  `Window` scene hosts the preferences/main UI, opened on demand.
//

import AppLockCore
import SwiftUI

/// Stable window identifiers used with `openWindow(id:)`.
enum AppWindowID {
    static let main = "main"
    static let about = "about"
    static let settings = "settings"
}

/// The `UserDefaults`/`@AppStorage` key for menu-bar icon visibility, shared by
/// the app entry and Preferences.
enum MenuBarPreference {
    static let key = "gg.tame.applock.showMenuBarIcon"
}

/// Bridges SwiftUI's `openWindow` action to AppKit code (the `AppDelegate`),
/// so reopening AppLock from Finder can surface the main window even when the
/// menu-bar icon is hidden.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var open: ((String) -> Void)?
}

@main
struct AppLockApp: App {
    /// The DI container for the whole process.
    private let environment = AppEnvironment.shared

    /// Bootstraps the locking engine and accessory activation policy.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var protectionViewModel: ProtectionViewModel

    init() {
        let env = AppEnvironment.shared
        _protectionViewModel = StateObject(wrappedValue: ProtectionViewModel(
            store: env.configurationStore,
            discoveryService: env.discoveryService
        ))
    }

    var body: some Scene {
        // The menu-bar item is managed in AppKit (StatusBarController) — see that
        // file for why MenuBarExtra isn't used.

        // Main window.
        Window("AppLock", id: AppWindowID.main) {
            MainView(viewModel: protectionViewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 640)
        .defaultLaunchBehavior(.presented)

        // About window.
        Window("About AppLock", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)

        // Preferences as a plain window (NOT the `Settings` scene): the Settings
        // scene installs a main-menu item that churns against the MenuBarExtra
        // and sends SwiftUI into an infinite scene-update loop on this macOS.
        Window("Preferences", id: AppWindowID.settings) {
            PreferencesView(
                store: environment.configurationStore,
                loginItem: environment.helperLoginItem
            )
        }
        .windowResizability(.contentSize)
    }
}
