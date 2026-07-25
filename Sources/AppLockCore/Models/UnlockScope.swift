//
//  UnlockScope.swift
//  AppLockCore
//
//  Describes the lifetime of a *temporary* unlock granted from the menu bar,
//  e.g. "Unlock Until Sleep". This is distinct from `RelockPolicy`, which is
//  the standing rule; an `UnlockScope` is a one-off, user-initiated grant.
//

import Foundation

/// The lifetime of a manually-granted unlock.
public enum UnlockScope: Codable, Hashable, Sendable {
    /// Valid until the next system sleep.
    case untilSleep
    /// Valid until the user logs out / the session ends.
    case untilLogout
    /// Valid for a fixed duration from the grant time.
    case forDuration(TimeInterval)

    public var displayName: String {
        switch self {
        case .untilSleep: "Until Sleep"
        case .untilLogout: "Until Logout"
        case .forDuration(let seconds): "For \(Int(seconds / 60)) min"
        }
    }
}

/// A concrete grant produced by an `UnlockScope`, tracked by `UnlockStateStore`.
public struct UnlockGrant: Hashable, Sendable {
    public let bundleIdentifier: String
    public let scope: UnlockScope
    public let grantedAt: Date
    /// Absolute expiry for `.forDuration` grants; `nil` for event-bound scopes.
    public let expiresAt: Date?

    public init(bundleIdentifier: String, scope: UnlockScope, grantedAt: Date = Date()) {
        self.bundleIdentifier = bundleIdentifier
        self.scope = scope
        self.grantedAt = grantedAt
        switch scope {
        case .forDuration(let seconds):
            self.expiresAt = grantedAt.addingTimeInterval(seconds)
        case .untilSleep, .untilLogout:
            self.expiresAt = nil
        }
    }

    /// Whether the grant has expired *by time* as of `now`. Event-bound grants
    /// (sleep/logout) never expire this way — they are revoked by their events.
    public func isTimeExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}
