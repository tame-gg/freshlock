//
//  RelockPolicy.swift
//  AppLockCore
//
//  Describes *when* a previously-unlocked application should become locked
//  again. The policy is evaluated by `RelockManager`; the model itself is a
//  pure, `Codable` value type so it can be persisted and unit-tested.
//

import Foundation

/// The condition under which an unlocked app returns to the locked state.
///
/// Each case maps directly to a user-facing "Auto Relock" option. Associated
/// values carry the parameter (minutes) where the option is configurable.
public enum RelockPolicy: Codable, Hashable, Sendable {
    /// Always require authentication on every launch/activation. Never grants a
    /// lasting unlock. This is the most secure option.
    case everyLaunch

    /// Relock once `minutes` have elapsed since the successful unlock.
    case afterMinutes(Int)

    /// Relock when the machine goes to sleep.
    case afterSleep

    /// Relock when the screen is locked (or the screen saver engages).
    case afterScreenLock

    /// Relock after `minutes` of user inactivity (no keyboard/mouse input).
    case afterInactivity(Int)

    /// Relock as soon as the user switches focus away from the protected app.
    case afterSwitchingAway

    /// Never relock automatically; only a manual "Lock" action relocks.
    case manualOnly

    /// A sensible default that balances security and convenience.
    public static let `default`: RelockPolicy = .afterSwitchingAway
}

public extension RelockPolicy {
    /// A stable, localization-independent identifier used for persistence and
    /// analytics-free logging.
    var kind: String {
        switch self {
        case .everyLaunch: "everyLaunch"
        case .afterMinutes: "afterMinutes"
        case .afterSleep: "afterSleep"
        case .afterScreenLock: "afterScreenLock"
        case .afterInactivity: "afterInactivity"
        case .afterSwitchingAway: "afterSwitchingAway"
        case .manualOnly: "manualOnly"
        }
    }

    /// Whether this policy can ever produce a lasting (cached) unlock. When
    /// `false`, the app must authenticate every single time it is activated.
    var grantsLastingUnlock: Bool {
        switch self {
        case .everyLaunch: false
        default: true
        }
    }
}
