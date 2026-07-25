//
//  UnlockStateStore.swift
//  FreshLockCore
//
//  Unlock state is keyed by **bundle identifier** (persistent app identity).
//  Each grant also records a `sessionPID` — the process that authenticated —
//  so a quit + relaunch (new PID) cannot reuse the previous unlock.
//
//  Queries never destroy grants. Only explicit `lock` / `revokeDeadSessions`
//  / time expiry remove them. (Earlier `isUnlocked` deleted grants on a PID
//  mismatch during quit/relaunch overlap, which cleared valid unlocks.)
//

import Foundation

@MainActor
public final class UnlockStateStore: ObservableObject {
    /// Grants keyed by bundle identifier.
    @Published public private(set) var grants: [String: UnlockGrant] = [:]

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Queries

    /// Whether this bundle is unlocked for the given live process.
    /// Does **not** mutate state on mismatch — returns `false` only.
    public func isUnlocked(_ bundleID: String, pid: pid_t) -> Bool {
        guard let grant = grants[bundleID] else { return false }
        if grant.isTimeExpired(asOf: now()) {
            return false
        }
        return grant.sessionPID == pid
    }

    /// Whether any non-expired grant exists for this bundle (UI / diagnostics).
    public func hasGrant(_ bundleID: String) -> Bool {
        guard let grant = grants[bundleID] else { return false }
        return !grant.isTimeExpired(asOf: now())
    }

    public var unlockedBundleIDs: Set<String> {
        Set(grants.keys.filter { hasGrant($0) })
    }

    // MARK: - Mutation

    public func grantUnlock(_ bundleID: String, scope: UnlockScope, sessionPID: pid_t) {
        grants[bundleID] = UnlockGrant(
            bundleIdentifier: bundleID,
            scope: scope,
            grantedAt: now(),
            sessionPID: sessionPID
        )
    }

    public func lock(_ bundleID: String) {
        grants[bundleID] = nil
    }

    public func lockAll() {
        grants.removeAll()
    }

    public func revokeGrants(matching predicate: (UnlockScope) -> Bool) {
        for (bundleID, grant) in grants where predicate(grant.scope) {
            grants[bundleID] = nil
        }
    }

    public func purgeTimeExpired() {
        let current = now()
        grants = grants.filter { !$0.value.isTimeExpired(asOf: current) }
    }

    /// Drop grants whose `sessionPID` is not among the live processes for that
    /// bundle. `livePIDsByBundle` maps bundle ID → set of currently running PIDs
    /// (empty / missing ⇒ process not running ⇒ revoke).
    @discardableResult
    public func revokeDeadSessions(livePIDsByBundle: [String: Set<pid_t>]) -> [String] {
        purgeTimeExpired()
        var revoked: [String] = []
        for (bundleID, grant) in grants {
            let live = livePIDsByBundle[bundleID] ?? []
            if !live.contains(grant.sessionPID) {
                grants[bundleID] = nil
                revoked.append(bundleID)
            }
        }
        return revoked
    }
}
