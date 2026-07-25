//
//  SettingsService.swift
//  FreshLockCore
//
//  Persists and loads the `Configuration` document. The protocol abstracts the
//  storage backend so tests use an in-memory or temp-directory store while the
//  app uses `~/Library/Application Support/FreshLock/configuration.json`.
//

import Foundation

/// Abstraction over configuration persistence.
public protocol SettingsServiceProtocol: Sendable {
    /// Load the persisted configuration, or a default one if none exists.
    func load() throws -> Configuration
    /// Atomically persist the configuration.
    func save(_ configuration: Configuration) throws
    /// The on-disk location of the configuration file (for export/backup UI).
    var storeURL: URL { get }
}

/// File-backed implementation writing JSON to a directory (Application Support
/// by default). Writes are atomic to avoid corruption on crash/power-loss.
public struct FileSettingsService: SettingsServiceProtocol {
    public let storeURL: URL

    /// - Parameter directory: the containing directory. Defaults to
    ///   `~/Library/Application Support/FreshLock`.
    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory(.default)
        self.storeURL = dir.appendingPathComponent("configuration.json")
    }

    private var fileManager: FileManager { .default }

    private static func defaultDirectory(_ fm: FileManager) -> URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FreshLock", isDirectory: true)
    }

    public func load() throws -> Configuration {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: storeURL)
        return try Configuration.decoded(from: data)
    }

    public func save(_ configuration: Configuration) throws {
        let dir = storeURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try configuration.encoded()
        // `.atomic` writes to a temp file then renames — never leaves a partial
        // configuration on disk.
        try data.write(to: storeURL, options: [.atomic])
        Log.settings.debug("Saved configuration (\(configuration.protectedApps.count) apps)")
    }
}
