//
//  RelockPolicy.swift
//  FreshLockCore
//
//  Describes *when* a previously-unlocked application should become locked
//  again. Event-based policies are evaluated by `RelockManager`; switch-away
//  and duration policies are applied by `LockCoordinator`. The model itself is
//  a pure, `Codable` value type so it can be persisted and unit-tested.
//

import Foundation

/// The condition under which an unlocked app returns to the locked state.
///
/// Each case maps directly to a user-facing "Auto Relock" option. Associated
/// values carry the parameter (minutes) where the option is configurable.
public enum RelockPolicy: Codable, Hashable, Sendable {
    /// Authenticate once when the app is opened, then stay unlocked until the
    /// app quits (or the Mac sleeps). Switching away and back does not re-prompt.
    /// The relock happens on app termination.
    case everyLaunch

    /// Relock once `minutes` have elapsed since the successful unlock.
    case afterMinutes(Int)

    /// Relock when the machine goes to sleep.
    case afterSleep

    /// Relock when the screen is locked (or the screen saver engages).
    case afterScreenLock

    /// Relock after `minutes` of user inactivity (no keyboard/mouse input).
    /// Tracked via system idle time (`CGEventSource`), not wall-clock since unlock.
    case afterInactivity(Int)

    /// Relock as soon as the user switches focus away from the protected app.
    case afterSwitchingAway

    /// Never relock automatically; only a manual "Lock" action relocks.
    case manualOnly

    /// The default, matching iOS app-lock: the app relocks the moment you switch
    /// away, so returning to it always re-authenticates.
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

    /// The minutes parameter for the parameterised cases (`.afterMinutes`,
    /// `.afterInactivity`); `nil` for the event- and launch-based cases.
    var minutes: Int? {
        switch self {
        case let .afterMinutes(m), let .afterInactivity(m): m
        default: nil
        }
    }

    /// Whether this policy can produce a lasting (cached) unlock rather than
    /// re-prompting on every activation. All policies now cache the unlock for
    /// their window; the global `requireEveryLaunch` setting is the master
    /// override that forces authentication on every activation.
    var grantsLastingUnlock: Bool {
        true
    }
}
