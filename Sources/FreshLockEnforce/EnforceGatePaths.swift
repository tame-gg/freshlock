//
//  EnforceGatePaths.swift
//  FreshLockEnforce
//
//  On-disk locations for the host ↔ Endpoint Security extension shared state.
//  The user-domain path is used while scaffolding / testing without a privileged
//  system extension. Production sysexts should prefer the machine-shared library
//  path so a root ES client and the user-session host see the same files.
//

import Foundation

/// Well-known paths for Phase 1 exec-gate shared state.
public enum EnforceGatePaths: Sendable {
    /// Bundle identifier of the Endpoint Security system extension.
    public static let extensionBundleIdentifier = "gg.tame.freshlock.enforce"

    /// Relative filenames inside the FreshLock support directory.
    public static let allowlistFileName = "enforce-allowlist.json"
    public static let lockedSetFileName = "enforce-locked.json"

    /// Per-user Application Support (host / unit tests / unprivileged runs).
    public static func userSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("FreshLock", isDirectory: true)
    }

    /// Machine-wide Application Support (preferred once the sysext runs as root).
    public static var sharedLibraryDirectory: URL {
        URL(fileURLWithPath: "/Library/Application Support/FreshLock", isDirectory: true)
    }

    public static func userAllowlistURL(fileManager: FileManager = .default) -> URL {
        userSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(allowlistFileName, isDirectory: false)
    }

    public static func userLockedSetURL(fileManager: FileManager = .default) -> URL {
        userSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(lockedSetFileName, isDirectory: false)
    }

    public static var sharedAllowlistURL: URL {
        sharedLibraryDirectory.appendingPathComponent(allowlistFileName, isDirectory: false)
    }

    public static var sharedLockedSetURL: URL {
        sharedLibraryDirectory.appendingPathComponent(lockedSetFileName, isDirectory: false)
    }
}
