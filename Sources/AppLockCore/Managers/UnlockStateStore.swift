//
//  UnlockStateStore.swift
//  AppLockCore
//
//  The single source of truth for "is app X currently unlocked?". It holds the
//  set of active unlock grants and answers lock/unlock questions. It contains
//  no timers and no system-event wiring — those live in `RelockManager`, which
//  drives this store. Keeping it pure makes the locking logic fully testable.
//

import Foundation

/// Tracks which apps are currently considered unlocked, and why.
///
/// Thread-safety: instances are `@MainActor`-isolated. All mutation happens on
/// the main actor, matching the UI/menu-bar interaction model. The store is
/// observable so SwiftUI can reflect lock state live.
@MainActor
public final class UnlockStateStore: ObservableObject {
    /// Active grants keyed by bundle identifier. A present grant means the app
    /// is currently unlocked.
    @Published public private(set) var grants: [String: UnlockGrant] = [:]

    /// A clock injection point so tests can control "now".
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Queries

    /// Whether the given app is unlocked as of the current time. Time-expired
    /// grants are treated as locked (and are lazily purged).
    public func isUnlocked(_ bundleID: String) -> Bool {
        guard let grant = grants[bundleID] else { return false }
        if grant.isTimeExpired(asOf: now()) {
            grants[bundleID] = nil
            return false
        }
        return true
    }

    public var unlockedBundleIDs: Set<String> {
        Set(grants.keys.filter { isUnlocked($0) })
    }

    // MARK: - Mutation

    /// Record a successful unlock for `bundleID` with the given scope.
    public func grantUnlock(_ bundleID: String, scope: UnlockScope) {
        grants[bundleID] = UnlockGrant(bundleIdentifier: bundleID, scope: scope, grantedAt: now())
    }

    /// Relock a single app.
    public func lock(_ bundleID: String) {
        grants[bundleID] = nil
    }

    /// Relock every currently-unlocked app (the "Lock All" action).
    public func lockAll() {
        grants.removeAll()
    }

    /// Revoke every grant whose scope is bound to a given system event.
    /// `RelockManager` calls this from the corresponding notification handler.
    public func revokeGrants(matching predicate: (UnlockScope) -> Bool) {
        for (bundleID, grant) in grants where predicate(grant.scope) {
            grants[bundleID] = nil
        }
    }

    /// Drop grants that have expired purely by elapsed time.
    public func purgeTimeExpired() {
        let current = now()
        grants = grants.filter { !$0.value.isTimeExpired(asOf: current) }
    }
}
