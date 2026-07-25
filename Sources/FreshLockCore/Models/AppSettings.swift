//
//  AppSettings.swift
//  FreshLockCore
//
//  The user's global preferences. This is a single `Codable` value type so the
//  whole configuration can be exported/imported and (eventually) synced via
//  iCloud as one document.
//

import Foundation

/// Global, app-wide preferences (as opposed to per-`ProtectedApp` overrides).
public struct AppSettings: Codable, Hashable, Sendable {
    /// Launch FreshLock automatically at login via `SMAppService`.
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

    /// Paranoid mode: relock on every focus switch-away (like `.afterSwitchingAway`
    /// for all apps), so returning to a protected app always re-authenticates.
    /// Does **not** destroy a live grant while that app stays frontmost - that
    /// previously caused an unlock→re-prompt loop after LocalAuthentication.
    public var requireEveryLaunch: Bool

    /// Enables verbose logging and diagnostic UI. Off by default.
    public var developerMode: Bool

    /// Minutes of inactivity used by `.afterInactivity` when a policy doesn't
    /// specify its own value.
    public var defaultInactivityMinutes: Int

    /// Global shortcut that immediately relocks every unlocked app. `nil` when
    /// the user hasn't assigned one.
    public var lockAllShortcut: GlobalShortcut?

    /// Global shortcut that authenticates once and unlocks all protected apps
    /// until sleep. `nil` when unassigned.
    public var unlockAllShortcut: GlobalShortcut?

    /// Prefer Apple's Liquid Glass materials for FreshLock chrome when the OS
    /// supports them (macOS 26+). Off uses classic system materials / solids.
    /// Does not override the system Appearance tint slider on macOS 27.
    public var preferLiquidGlass: Bool

    public init(
        launchAtLogin: Bool = false,
        gracePeriodSeconds: Int = 30,
        defaultRelockPolicy: RelockPolicy = .default,
        overlayStyle: OverlayStyle = .default,
        notifyOnProtectedLaunch: Bool = false,
        requireEveryLaunch: Bool = false,
        developerMode: Bool = false,
        defaultInactivityMinutes: Int = 5,
        lockAllShortcut: GlobalShortcut? = nil,
        unlockAllShortcut: GlobalShortcut? = nil,
        preferLiquidGlass: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.gracePeriodSeconds = gracePeriodSeconds
        self.defaultRelockPolicy = defaultRelockPolicy
        self.overlayStyle = overlayStyle
        self.notifyOnProtectedLaunch = notifyOnProtectedLaunch
        self.requireEveryLaunch = requireEveryLaunch
        self.developerMode = developerMode
        self.defaultInactivityMinutes = defaultInactivityMinutes
        self.lockAllShortcut = lockAllShortcut
        self.unlockAllShortcut = unlockAllShortcut
        self.preferLiquidGlass = preferLiquidGlass
    }

    public static let `default` = AppSettings()

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case gracePeriodSeconds
        case defaultRelockPolicy
        case overlayStyle
        case notifyOnProtectedLaunch
        case requireEveryLaunch
        case developerMode
        case defaultInactivityMinutes
        case lockAllShortcut
        case unlockAllShortcut
        case preferLiquidGlass
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        gracePeriodSeconds = try c.decodeIfPresent(Int.self, forKey: .gracePeriodSeconds) ?? 30
        defaultRelockPolicy = try c.decodeIfPresent(RelockPolicy.self, forKey: .defaultRelockPolicy) ?? .default
        overlayStyle = try c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle) ?? .default
        notifyOnProtectedLaunch = try c.decodeIfPresent(Bool.self, forKey: .notifyOnProtectedLaunch) ?? false
        requireEveryLaunch = try c.decodeIfPresent(Bool.self, forKey: .requireEveryLaunch) ?? false
        developerMode = try c.decodeIfPresent(Bool.self, forKey: .developerMode) ?? false
        defaultInactivityMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultInactivityMinutes) ?? 5
        lockAllShortcut = try c.decodeIfPresent(GlobalShortcut.self, forKey: .lockAllShortcut)
        unlockAllShortcut = try c.decodeIfPresent(GlobalShortcut.self, forKey: .unlockAllShortcut)
        // Older configs omit this key; default on so macOS 26+ picks up glass.
        preferLiquidGlass = try c.decodeIfPresent(Bool.self, forKey: .preferLiquidGlass) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(gracePeriodSeconds, forKey: .gracePeriodSeconds)
        try c.encode(defaultRelockPolicy, forKey: .defaultRelockPolicy)
        try c.encode(overlayStyle, forKey: .overlayStyle)
        try c.encode(notifyOnProtectedLaunch, forKey: .notifyOnProtectedLaunch)
        try c.encode(requireEveryLaunch, forKey: .requireEveryLaunch)
        try c.encode(developerMode, forKey: .developerMode)
        try c.encode(defaultInactivityMinutes, forKey: .defaultInactivityMinutes)
        try c.encodeIfPresent(lockAllShortcut, forKey: .lockAllShortcut)
        try c.encodeIfPresent(unlockAllShortcut, forKey: .unlockAllShortcut)
        try c.encode(preferLiquidGlass, forKey: .preferLiquidGlass)
    }
}
