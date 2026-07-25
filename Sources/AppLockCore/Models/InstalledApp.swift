//
//  InstalledApp.swift
//  AppLockCore
//
//  An application discovered on disk by `AppDiscoveryService`. This is the
//  read-only "catalogue" representation — protection state lives separately in
//  `ProtectedApp` so that discovery and configuration stay decoupled.
//

import Foundation

/// Metadata for an application installed on the system.
///
/// Deliberately free of any AppKit types (no `NSImage`) so it can live in the
/// core library and be encoded/tested trivially. The icon is referenced by the
/// app's file URL; the UI layer resolves the actual image lazily via
/// `NSWorkspace`.
public struct InstalledApp: Identifiable, Hashable, Sendable, Codable {
    /// Stable identity: the bundle identifier is the primary key throughout the
    /// app. Two bundles with the same identifier are treated as the same app.
    public var id: String { bundleIdentifier }

    /// e.g. `com.apple.Safari`.
    public let bundleIdentifier: String

    /// Localised display name, e.g. "Safari".
    public let name: String

    /// Absolute path to the `.app` bundle on disk.
    public let path: String

    /// Bundle version string (`CFBundleShortVersionString`), when available.
    public let version: String?

    public init(bundleIdentifier: String, name: String, path: String, version: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.version = version
    }

    /// File URL of the bundle, convenient for icon resolution.
    public var url: URL { URL(fileURLWithPath: path) }
}
