//
//  ProtectedApp.swift
//  FreshLockCore
//
//  The user's configuration for a single protected application. This is the
//  persisted unit of "what FreshLock guards and how". It references an app by
//  bundle identifier rather than embedding an `InstalledApp` so that config
//  survives app updates, moves, and reinstalls.
//

import Foundation

/// A single entry in the user's protection list.
public struct ProtectedApp: Identifiable, Hashable, Sendable, Codable {
    public var id: String { bundleIdentifier }

    /// Primary key — matches `InstalledApp.bundleIdentifier`.
    public let bundleIdentifier: String

    /// Cached display name, so the list still renders if the app is temporarily
    /// unavailable (e.g. on an unmounted volume).
    public var name: String

    /// Last-known install path, used as a fallback for icon display.
    public var path: String

    /// Whether protection is currently active for this app.
    public var isEnabled: Bool

    /// Whether the user marked this app as a favourite (pins it to the top).
    public var isFavorite: Bool

    /// Organisational grouping.
    public var category: AppCategory

    /// Per-app override of when to relock. When `nil`, the global default from
    /// `Settings` applies.
    public var relockPolicy: RelockPolicy?

    /// Number of consecutive failed authentications after which the app should
    /// be terminated. `nil` disables the behaviour.
    public var terminateAfterFailures: Int?

    public init(
        bundleIdentifier: String,
        name: String,
        path: String,
        isEnabled: Bool = true,
        isFavorite: Bool = false,
        category: AppCategory = .other,
        relockPolicy: RelockPolicy? = nil,
        terminateAfterFailures: Int? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.isFavorite = isFavorite
        self.category = category
        self.relockPolicy = relockPolicy
        self.terminateAfterFailures = terminateAfterFailures
    }

    /// Convenience initialiser from a freshly-discovered app.
    ///
    /// A newly-created entry is **not** protected until the user explicitly
    /// enables it — otherwise the first tap of the protection toggle would flip
    /// a defaulted-on value back off.
    public init(from installed: InstalledApp, category: AppCategory = .other) {
        self.init(
            bundleIdentifier: installed.bundleIdentifier,
            name: installed.name,
            path: installed.path,
            isEnabled: false,
            category: category
        )
    }

    /// The effective relock policy, resolving the per-app override against a
    /// supplied global default.
    public func effectiveRelockPolicy(default globalDefault: RelockPolicy) -> RelockPolicy {
        relockPolicy ?? globalDefault
    }
}
