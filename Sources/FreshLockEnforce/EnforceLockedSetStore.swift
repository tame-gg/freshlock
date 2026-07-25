//
//  EnforceLockedSetStore.swift
//  FreshLockEnforce
//
//  On-disk set of signing IDs that must not exec unless unlocked. Written by
//  the host/helper from the protected-app configuration; read by the ES
//  extension on AUTH_EXEC.
//

import Foundation

/// Atomic JSON store for the locked signing-ID set.
public struct EnforceLockedSetStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL(
        fileManager: FileManager = .default
    ) -> EnforceLockedSetStore {
        EnforceLockedSetStore(fileURL: EnforceGatePaths.userLockedSetURL(fileManager: fileManager))
    }

    public static func sharedLibraryURL() -> EnforceLockedSetStore {
        EnforceLockedSetStore(fileURL: EnforceGatePaths.sharedLockedSetURL)
    }

    public func load() throws -> Set<String> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(LockedSetPayload.self, from: data)
        return Set(decoded.lockedSigningIDs)
    }

    /// Write the locked set, skipping the write entirely when the on-disk bytes
    /// already match. `.atomic` performs the temp-file + rename itself, so this
    /// is one filesystem mutation rather than write/remove/move.
    public func save(_ lockedSigningIDs: Set<String>) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = LockedSetPayload(lockedSigningIDs: lockedSigningIDs.sorted())
        let data = try JSONEncoder().encode(payload)
        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private struct LockedSetPayload: Codable {
        var lockedSigningIDs: [String]
    }
}
