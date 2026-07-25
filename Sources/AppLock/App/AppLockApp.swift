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
        // Menu-bar presence — the always-on face of the app.
        MenuBarExtra("AppLock", systemImage: "lock.shield.fill") {
            MenuBarContent(viewModel: protectionViewModel, unlockStore: environment.unlockStore)
        }
        .menuBarExtraStyle(.menu)

        // Main / preferences window.
        Window("AppLock", id: AppWindowID.main) {
            MainView(viewModel: protectionViewModel)
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowResizability(.contentMinSize)

        // About window.
        Window("About AppLock", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)

        // Preferences via the standard ⌘, menu item.
        Settings {
            PreferencesView(
                store: environment.configurationStore,
                loginItem: environment.helperLoginItem
            )
        }
    }
}
