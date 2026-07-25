//
//  UnlockScope.swift
//  FreshLockCore
//
//  Describes the lifetime of a temporary unlock. An unlock is always bound to
//  a concrete process ID (`sessionPID`). When that process exits, the grant is
//  invalid — a relaunch is a new session and must re-authenticate.
//

import Foundation

/// The lifetime of a manually-granted or policy-granted unlock.
public enum UnlockScope: Codable, Hashable, Sendable {
    /// Valid until the next system sleep (and only while `sessionPID` lives).
    case untilSleep
    /// Valid until logout (and only while `sessionPID` lives).
    case untilLogout
    /// Valid for a fixed wall-clock duration (and only while `sessionPID` lives).
    case forDuration(TimeInterval)
    /// Valid until the user has been idle (no keyboard/mouse input) for the
    /// given interval. Unlike ``forDuration``, the clock resets on each input.
    case untilInactivity(TimeInterval)

    public var displayName: String {
        switch self {
        case .untilSleep: "Until Sleep"
        case .untilLogout: "Until Logout"
        case let .forDuration(seconds): "For \(Int(seconds / 60)) min"
        case let .untilInactivity(seconds): "After \(Int(seconds / 60)) min idle"
        }
    }

    /// Idle threshold for ``untilInactivity``; `nil` for other scopes.
    public var inactivityThreshold: TimeInterval? {
        if case let .untilInactivity(seconds) = self {
            return seconds
        }
        return nil
    }
}

/// A concrete unlock grant. **Security invariant:** a grant is only valid while
/// the recorded `sessionPID` is still the live process for that bundle ID.
public struct UnlockGrant: Hashable, Sendable {
    public let bundleIdentifier: String
    public let scope: UnlockScope
    public let grantedAt: Date
    public let expiresAt: Date?
    /// The protected app process that authenticated. Required — no fail-open.
    public let sessionPID: pid_t

    public init(
        bundleIdentifier: String,
        scope: UnlockScope,
        grantedAt: Date = Date(),
        sessionPID: pid_t
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.scope = scope
        self.grantedAt = grantedAt
        self.sessionPID = sessionPID
        switch scope {
        case let .forDuration(seconds):
            expiresAt = grantedAt.addingTimeInterval(seconds)
        case .untilSleep, .untilLogout, .untilInactivity:
            expiresAt = nil
        }
    }

    public func isTimeExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Whether this grant is still inside the post-unlock grace window.
    public func isWithinGracePeriod(_ seconds: Int, asOf now: Date = Date()) -> Bool {
        guard seconds > 0 else { return false }
        return now.timeIntervalSince(grantedAt) < TimeInterval(seconds)
    }

    /// Valid only for this exact running process.
    public func isValid(forPID pid: pid_t) -> Bool {
        sessionPID == pid
    }
}
