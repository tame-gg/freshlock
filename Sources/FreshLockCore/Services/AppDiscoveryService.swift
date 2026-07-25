//
//  AppDiscoveryService.swift
//  FreshLockCore
//
//  Enumerates installed `.app` bundles by scanning the standard application
//  directories and reading each bundle's `Info.plist`. We deliberately avoid
//  `NSWorkspace`/`LSCopyApplicationURLsForBundleIdentifier` here so the core
//  library stays free of AppKit and remains unit-testable against a temp
//  directory of fixture bundles.
//

import Foundation

/// Discovers applications installed on the system.
public protocol AppDiscoveryServiceProtocol: Sendable {
    /// Scan the configured search locations and return discovered apps, sorted
    /// by display name.
    func discoverApps() -> [InstalledApp]
}

/// Filesystem-backed discovery.
public struct AppDiscoveryService: AppDiscoveryServiceProtocol {
    /// Directories to scan for `.app` bundles.
    private let searchPaths: [URL]

    /// - Parameter searchPaths: override for testing. Defaults to the system
    ///   and user Applications folders (including `Utilities`).
    public init(searchPaths: [URL]? = nil) {
        self.searchPaths = searchPaths ?? Self.defaultSearchPaths(.default)
    }

    private var fileManager: FileManager {
        .default
    }

    private static func defaultSearchPaths(_ fm: FileManager) -> [URL] {
        var paths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]
        if let userApps = fm.urls(for: .applicationDirectory, in: .userDomainMask).first {
            paths.append(userApps)
        }
        return paths
    }

    public func discoverApps() -> [InstalledApp] {
        var byBundleID: [String: InstalledApp] = [:]

        for directory in searchPaths {
            for entry in Self.appBundles(in: directory, fileManager: fileManager) {
                guard let app = Self.makeInstalledApp(from: entry) else { continue }
                // First writer wins; user /Applications is scanned before /System
                // so user copies take precedence over duplicates.
                if byBundleID[app.bundleIdentifier] == nil {
                    byBundleID[app.bundleIdentifier] = app
                }
            }
        }

        return byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Top-level `.app` bundles plus one nesting level (e.g. `/Applications/Setapp/*.app`).
    private static func appBundles(in directory: URL, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var apps: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                apps.append(entry)
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let nested = try? fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            apps.append(contentsOf: nested.filter { $0.pathExtension == "app" })
        }
        return apps
    }

    /// Read the minimal metadata we need out of a bundle's `Info.plist`.
    static func makeInstalledApp(from bundleURL: URL) -> InstalledApp? {
        let infoPlist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let bundleID = dict["CFBundleIdentifier"] as? String
        else {
            return nil
        }

        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = dict["CFBundleShortVersionString"] as? String

        return InstalledApp(
            bundleIdentifier: bundleID,
            name: name,
            path: bundleURL.path,
            version: version
        )
    }
}
