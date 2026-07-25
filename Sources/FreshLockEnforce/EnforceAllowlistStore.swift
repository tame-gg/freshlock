//
//  EnforceAllowlistStore.swift
//  FreshLockEnforce
//
//  On-disk unlock allowlist shared between the host/helper (writes after LA)
//  and the ES system extension (reads on AUTH_EXEC). File-based so the
//  extension can start before XPC is up; XPC can mirror the same state later.
//
//  This is not a secret store — it only lists which signing IDs may exec.
//

import Foundation

/// Atomic JSON store for ``UnlockAllowlist``.
public struct EnforceAllowlistStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location beside FreshLock's configuration (user Application Support).
    public static func defaultURL(
        fileManager: FileManager = .default
    ) -> EnforceAllowlistStore {
        EnforceAllowlistStore(fileURL: EnforceGatePaths.userAllowlistURL(fileManager: fileManager))
    }

    /// Machine-shared path for a privileged system extension + host.
    public static func sharedLibraryURL() -> EnforceAllowlistStore {
        EnforceAllowlistStore(fileURL: EnforceGatePaths.sharedAllowlistURL)
    }

    public func load() throws -> UnlockAllowlist {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return UnlockAllowlist()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(UnlockAllowlist.self, from: data)
    }

    /// Write the allowlist, skipping the write entirely when the on-disk bytes
    /// already match. `.atomic` performs the temp-file + rename itself, so this
    /// is one filesystem mutation rather than write/remove/move.
    public func save(_ allowlist: UnlockAllowlist) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(allowlist)
        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
