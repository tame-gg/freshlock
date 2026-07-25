//
//  ConfigurationStore.swift
//  FreshLock
//
//  The single in-memory source of truth for the FreshLock `Configuration` in the
//  GUI process. Both the protection list and the preferences screen read and
//  mutate *this* object, so edits never clobber one another (previously each
//  view model held its own copy and the last save won). Every mutation persists
//  atomically through the injected `SettingsServiceProtocol`.
//

import Foundation
import FreshLockCore

@MainActor
final class ConfigurationStore: ObservableObject {
    /// The live configuration. Views observe this; mutate only via `update`.
    @Published private(set) var configuration: Configuration

    private let settingsService: SettingsServiceProtocol

    init(settingsService: SettingsServiceProtocol) {
        self.settingsService = settingsService
        configuration = (try? settingsService.load()) ?? .empty
    }

    /// Apply an in-place change and persist. All mutations funnel through here.
    func update(_ mutate: (inout Configuration) -> Void) {
        mutate(&configuration)
        persist()
    }

    /// Replace the entire configuration (used by import) and persist.
    func replace(with newValue: Configuration) {
        configuration = newValue
        persist()
    }

    // MARK: - Import / export

    /// Serialise the current configuration to a file URL.
    func export(to url: URL) throws {
        try configuration.encoded().write(to: url, options: [.atomic])
    }

    /// Load and adopt a configuration document from disk.
    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try replace(with: Configuration.decoded(from: data))
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try settingsService.save(configuration)
        } catch {
            Log.settings.error("Failed to persist configuration: \(error.localizedDescription)")
        }
    }
}
