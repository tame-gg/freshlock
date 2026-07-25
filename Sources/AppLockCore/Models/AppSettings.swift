//
//  AppSettings.swift
//  AppLockCore
//
//  The user's global preferences. This is a single `Codable` value type so the
//  whole configuration can be exported/imported and (eventually) synced via
//  iCloud as one document.
//

import Foundation

/// Global, app-wide preferences (as opposed to per-`ProtectedApp` overrides).
public struct AppSettings: Codable, Hashable, Sendable {
    /// Launch AppLock automatically at login via `SMAppService`.
    public var launchAtLogin: Bool

    /// Grace period, in seconds, during which a freshly-unlocked app will not
    /// re-prompt even under aggressive relock policies. Prevents prompt storms
    /// when apps rapidly resign/regain focus.
    public var gracePeriodSeconds: Int

    /// Default relock policy applied to apps that don't set their own.
    public var defaultRelockPolicy: RelockPolicy

    /// Overlay appearance.
    public var overlayStyle: OverlayStyle

    /// Post a user notification whenever a protected app launches.
    public var notifyOnProtectedLaunch: Bool

    /// Force authentication on every activation regardless of per-app policy.
    /// This is a global "paranoid mode" master switch.
    public var requireEveryLaunch: Bool

    /// Enables verbose logging and diagnostic UI. Off by default.
    public var developerMode: Bool

    /// Minutes of inactivity used by `.afterInactivity` when a policy doesn't
    /// specify its own value.
    public var defaultInactivityMinutes: Int

    public init(
        launchAtLogin: Bool = false,
        gracePeriodSeconds: Int = 3,
        defaultRelockPolicy: RelockPolicy = .default,
        overlayStyle: OverlayStyle = .default,
        notifyOnProtectedLaunch: Bool = false,
        requireEveryLaunch: Bool = false,
        developerMode: Bool = false,
        defaultInactivityMinutes: Int = 5
    ) {
        self.launchAtLogin = launchAtLogin
        self.gracePeriodSeconds = gracePeriodSeconds
        self.defaultRelockPolicy = defaultRelockPolicy
        self.overlayStyle = overlayStyle
        self.notifyOnProtectedLaunch = notifyOnProtectedLaunch
        self.requireEveryLaunch = requireEveryLaunch
        self.developerMode = developerMode
        self.defaultInactivityMinutes = defaultInactivityMinutes
    }

    public static let `default` = AppSettings()
}
