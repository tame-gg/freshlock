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

    /// Whether a non-expired grant exists whose `sessionPID` is still among the
    /// live processes for this bundle (Electron / multi-process apps).
    public func isUnlockedWhileAlive(_ bundleID: String, livePIDs: Set<pid_t>) -> Bool {
        guard let grant = grants[bundleID] else { return false }
        if grant.isTimeExpired(asOf: now()) {
            return false
        }
        return livePIDs.contains(grant.sessionPID)
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
        guard grants[bundleID] != nil else { return }
        grants[bundleID] = nil
    }

    public func lockAll() {
        guard !grants.isEmpty else { return }
        grants.removeAll()
    }

    /// Revoke every grant whose scope matches. Applied as a single mutation so
    /// observers see one change rather than one per revoked grant.
    public func revokeGrants(matching predicate: (UnlockScope) -> Bool) {
        let survivors = grants.filter { !predicate($0.value.scope) }
        guard survivors.count != grants.count else { return }
        grants = survivors
    }

    /// Drop grants past their time limit.
    ///
    /// Only assigns when something actually expired. The unconditional
    /// reassignment this replaces fired `@Published` on every liveness poll,
    /// which drove a downstream disk write several times a second.
    public func purgeTimeExpired() {
        let current = now()
        let survivors = grants.filter { !$0.value.isTimeExpired(asOf: current) }
        guard survivors.count != grants.count else { return }
        grants = survivors
    }

    /// Drop grants whose `sessionPID` is not among the live processes for that
    /// bundle. `livePIDsByBundle` maps bundle ID → set of currently running PIDs
    /// (empty / missing ⇒ process not running ⇒ revoke).
    @discardableResult
    public func revokeDeadSessions(livePIDsByBundle: [String: Set<pid_t>]) -> [String] {
        purgeTimeExpired()
        var revoked: [String] = []
        var survivors: [String: UnlockGrant] = [:]
        survivors.reserveCapacity(grants.count)
        for (bundleID, grant) in grants {
            if livePIDsByBundle[bundleID]?.contains(grant.sessionPID) == true {
                survivors[bundleID] = grant
            } else {
                revoked.append(bundleID)
            }
        }
        guard !revoked.isEmpty else { return [] }
        grants = survivors
        return revoked
    }
}
