//
//  SettingsViewModel.swift
//  AppLock
//
//  Backs the Preferences window. It edits the global `AppSettings` slice of the
//  shared `ConfigurationStore` and manages the launch-at-login login item and
//  configuration import/export. Because it shares the store with the main
//  window, changes made here are reflected everywhere immediately.
//

import AppLockCore
import AppLockEngine
import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    /// A working copy of the settings, bound to the UI. Committed to the store
    /// on each change via `didSet`.
    @Published var settings: AppSettings {
        didSet { commit(previous: oldValue) }
    }

    /// Surfaced to the UI when registering the login item fails.
    @Published var loginItemError: String?

    private let store: ConfigurationStore
    private let loginItem: LoginItemServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    /// Guards against feedback loops when we adopt store-driven changes.
    private var isSyncingFromStore = false

    init(store: ConfigurationStore, loginItem: LoginItemServiceProtocol) {
        self.store = store
        self.loginItem = loginItem
        // Reconcile the persisted launch-at-login flag with the real system
        // state and assign `settings` EXACTLY ONCE. A second assignment would
        // fire `didSet` → `commit` → `store.update` *during* view construction,
        // which mutates observed state mid-update and crashes SwiftUI with a
        // re-entrant graph loop (stack overflow).
        var reconciled = store.configuration.settings
        reconciled.launchAtLogin = loginItem.isEnabled
        self.settings = reconciled

        // Keep the working copy in sync if the store changes elsewhere (import).
        store.objectWillChange
            .sink { [weak self] _ in self?.adoptStoreSettings() }
            .store(in: &cancellables)
    }

    private func adoptStoreSettings() {
        let incoming = store.configuration.settings
        guard incoming != settings else { return }
        isSyncingFromStore = true
        settings = incoming
        isSyncingFromStore = false
    }

    private func commit(previous: AppSettings) {
        guard !isSyncingFromStore else { return }
        if settings.launchAtLogin != previous.launchAtLogin {
            applyLaunchAtLogin(settings.launchAtLogin)
        }
        store.update { $0.settings = settings }
    }

    /// Register/unregister the background helper as a login item. On failure we
    /// revert the toggle so the UI never claims a state the system rejected.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't \(enabled ? "enable" : "disable") launch at login. " +
                "Make sure AppLock is in your Applications folder."
            Log.settings.error("Login item toggle failed: \(error.localizedDescription)")
            settings.launchAtLogin = loginItem.isEnabled
        }
    }

    // MARK: - Import / export (delegated to the shared store)

    func exportConfiguration(to url: URL) throws {
        try store.export(to: url)
    }

    func importConfiguration(from url: URL) throws {
        try store.importConfiguration(from: url)
        adoptStoreSettings()
    }
}
