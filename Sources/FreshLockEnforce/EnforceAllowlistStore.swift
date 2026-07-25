//
//  EnforceAllowlistStore.swift
//  FreshLockEnforce
//
//  On-disk unlock allowlist shared between the host/helper (writes after LA)
//  and the future ES system extension (reads on AUTH_EXEC). File-based so the
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

    /// Default location beside FreshLock's configuration.
    public static func defaultURL(
        fileManager: FileManager = .default
    ) -> EnforceAllowlistStore {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = support.appendingPathComponent("FreshLock", isDirectory: true)
        return EnforceAllowlistStore(
            fileURL: dir.appendingPathComponent("enforce-allowlist.json", isDirectory: false)
        )
    }

    public func load() throws -> UnlockAllowlist {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return UnlockAllowlist()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(UnlockAllowlist.self, from: data)
    }

    public func save(_ allowlist: UnlockAllowlist) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(allowlist)
        let temp = fileURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try? fm.removeItem(at: fileURL)
        try fm.moveItem(at: temp, to: fileURL)
    }
}
