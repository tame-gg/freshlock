//
//  SettingsViewModel.swift
//  AppLock
//
//  Backs the Preferences window. Wraps the global `AppSettings` slice of the
//  configuration and persists on every change, so preferences feel instant and
//  survive relaunch.
//

import AppLockCore
import AppLockEngine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist(previous: oldValue) }
    }

    /// Surfaced to the UI when registering the login item fails (e.g. the app
    /// isn't in /Applications yet).
    @Published var loginItemError: String?

    private let settingsService: SettingsServiceProtocol
    private let loginItem: LoginItemServiceProtocol
    private var configuration: Configuration

    init(
        settingsService: SettingsServiceProtocol,
        loginItem: LoginItemServiceProtocol,
        initialConfiguration: Configuration
    ) {
        self.settingsService = settingsService
        self.loginItem = loginItem
        self.configuration = initialConfiguration
        self.settings = initialConfiguration.settings
        // Reconcile the persisted preference with the real system state.
        self.settings.launchAtLogin = loginItem.isEnabled
    }

    private func persist(previous: AppSettings) {
        if settings.launchAtLogin != previous.launchAtLogin {
            applyLaunchAtLogin(settings.launchAtLogin)
        }
        configuration.settings = settings
        do {
            try settingsService.save(configuration)
        } catch {
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
        }
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

    /// Export the entire configuration to a JSON file.
    func exportConfiguration(to url: URL) throws {
        configuration.settings = settings
        try configuration.encoded().write(to: url, options: [.atomic])
    }

    /// Import a configuration document, replacing the current one.
    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try Configuration.decoded(from: data)
        configuration = imported
        settings = imported.settings
        try settingsService.save(configuration)
    }
}
