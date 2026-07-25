//
//  Configuration.swift
//  FreshLockCore
//
//  The complete, serialisable FreshLock configuration: the global settings plus
//  the list of protected apps. This single document is what gets persisted,
//  exported to disk, imported, backed up, and (in future) synced via iCloud.
//

import Foundation

/// The root persisted document for FreshLock.
public struct Configuration: Codable, Hashable, Sendable {
    /// Schema version, to allow forward-compatible migrations.
    public var schemaVersion: Int

    public var settings: AppSettings

    public var protectedApps: [ProtectedApp]

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = Configuration.currentSchemaVersion,
        settings: AppSettings = .default,
        protectedApps: [ProtectedApp] = []
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.protectedApps = protectedApps
    }

    public static let empty = Configuration()

    // MARK: - Convenience accessors

    public func protectedApp(for bundleID: String) -> ProtectedApp? {
        protectedApps.first { $0.bundleIdentifier == bundleID }
    }

    public var enabledProtectedApps: [ProtectedApp] {
        protectedApps.filter(\.isEnabled)
    }

    // MARK: - JSON round-tripping (import / export / backup)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encode to pretty-printed JSON `Data`, suitable for writing to disk.
    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Decode from JSON `Data`. Throws on malformed input or unsupported schema.
    public static func decoded(from data: Data) throws -> Configuration {
        let config = try decoder.decode(Configuration.self, from: data)
        guard config.schemaVersion <= currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema(config.schemaVersion)
        }
        return config
    }
}

/// Errors raised while (de)serialising configuration.
public enum ConfigurationError: Error, Equatable, Sendable {
    /// The document was written by a newer version of FreshLock than this build
    /// understands.
    case unsupportedSchema(Int)
}
