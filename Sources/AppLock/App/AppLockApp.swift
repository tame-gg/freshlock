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

    /// Two-way binding to the "show menu bar icon" preference, so toggling it in
    /// Preferences inserts/removes the `MenuBarExtra` live.
    private var showMenuBarIcon: Binding<Bool> {
        Binding(
            get: { protectionViewModel.configuration.settings.showMenuBarIcon },
            set: { newValue in
                environment.configurationStore.update { $0.settings.showMenuBarIcon = newValue }
            }
        )
    }

    var body: some Scene {
        // Menu-bar presence — the always-on face of the app (user can hide it).
        MenuBarExtra("AppLock", systemImage: "lock.shield.fill", isInserted: showMenuBarIcon) {
            MenuBarContent(viewModel: protectionViewModel, unlockStore: environment.unlockStore)
        }
        .menuBarExtraStyle(.menu)

        // Main window.
        Window("AppLock", id: AppWindowID.main) {
            MainView(viewModel: protectionViewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 640)

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
