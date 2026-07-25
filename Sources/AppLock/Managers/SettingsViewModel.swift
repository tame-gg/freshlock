//
//  SettingsViewModel.swift
//  AppLock
//
//  Backs the Preferences window. Wraps the global `AppSettings` slice of the
//  configuration and persists on every change, so preferences feel instant and
//  survive relaunch.
//

import AppLockCore
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let settingsService: SettingsServiceProtocol
    private var configuration: Configuration

    init(settingsService: SettingsServiceProtocol, initialConfiguration: Configuration) {
        self.settingsService = settingsService
        self.configuration = initialConfiguration
        self.settings = initialConfiguration.settings
    }

    private func persist() {
        configuration.settings = settings
        do {
            try settingsService.save(configuration)
        } catch {
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
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
