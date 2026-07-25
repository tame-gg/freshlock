//
//  SettingsViewModel.swift
//  FreshLock
//
//  Backs the Preferences window. Every control binds *directly* to a single
//  field of the shared `ConfigurationStore` via `binding(_:)`, which writes only
//  that one field. There is deliberately no separate `settings` working copy and
//  no "adopt from store" round-trip: the previous design read the store back
//  inside its own `objectWillChange` (which fires in `willSet`, before the new
//  value lands), so it read a *stale* value and clobbered unrelated preferences
//  — most visibly, changing the overlay style turned "Launch at Login" off.
//

import FreshLockCore
import FreshLockEngine
import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    /// Surfaced to the UI when registering the login item fails.
    @Published var loginItemError: String?

    let store: ConfigurationStore
    private let loginItem: LoginItemServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(store: ConfigurationStore, loginItem: LoginItemServiceProtocol) {
        self.store = store
        self.loginItem = loginItem
        // Re-render when the store changes (e.g. an import), so the controls
        // reflect the latest values. We never mutate the store from here.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Read-only snapshot for display-only values.
    var settings: AppSettings { store.configuration.settings }

    /// A binding to a single settings field. The setter writes **only** that
    /// field through the shared store, so unrelated preferences are never
    /// touched or reset.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.store.configuration.settings[keyPath: keyPath] },
            set: { newValue in self.store.update { $0.settings[keyPath: keyPath] = newValue } }
        )
    }

    /// Launch-at-login is bound to the **real** login-item state, not the stored
    /// mirror, so it is completely independent of any other settings write.
    var launchAtLogin: Binding<Bool> {
        Binding(get: { self.loginItem.isEnabled }, set: { self.setLaunchAtLogin($0) })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't \(enabled ? "enable" : "disable") launch at login. " +
                "Make sure FreshLock is in your Applications folder."
            Log.settings.error("Login item toggle failed: \(error.localizedDescription)")
        }
        // Mirror the *actual* resulting state into the persisted config (so it's
        // captured in exports) without touching any other field.
        store.update { $0.settings.launchAtLogin = loginItem.isEnabled }
    }

    // MARK: - Import / export (delegated to the shared store)

    func exportConfiguration(to url: URL) throws {
        try store.export(to: url)
    }

    func importConfiguration(from url: URL) throws {
        try store.importConfiguration(from: url)
    }
}
