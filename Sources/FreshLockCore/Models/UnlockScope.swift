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
    /// Valid for a fixed duration (and only while `sessionPID` lives).
    case forDuration(TimeInterval)

    public var displayName: String {
        switch self {
        case .untilSleep: "Until Sleep"
        case .untilLogout: "Until Logout"
        case .forDuration(let seconds): "For \(Int(seconds / 60)) min"
        }
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
        case .forDuration(let seconds):
            self.expiresAt = grantedAt.addingTimeInterval(seconds)
        case .untilSleep, .untilLogout:
            self.expiresAt = nil
        }
    }

    public func isTimeExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Valid only for this exact running process.
    public func isValid(forPID pid: pid_t) -> Bool {
        sessionPID == pid
    }
}
