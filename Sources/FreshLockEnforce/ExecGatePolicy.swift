//
//  ExecGatePolicy.swift
//  FreshLockEnforce
//
//  Pure allow/deny policy for AUTH_EXEC-style gates. No EndpointSecurity import
//  so it stays unit-testable under `swift test`.
//

import Foundation

/// Snapshot of which signing IDs are currently allowed to exec.
public struct UnlockAllowlist: Hashable, Sendable, Codable {
    /// Signing IDs that have a valid unlock grant.
    public var allowedSigningIDs: Set<String>

    public init(allowedSigningIDs: Set<String> = []) {
        self.allowedSigningIDs = allowedSigningIDs
    }

    public func allowing(_ signingID: String) -> UnlockAllowlist {
        var copy = self
        copy.allowedSigningIDs.insert(signingID)
        return copy
    }

    public func revoking(_ signingID: String) -> UnlockAllowlist {
        var copy = self
        copy.allowedSigningIDs.remove(signingID)
        return copy
    }
}

/// Locked-set + always-allow set consulted on every exec decision.
public struct ExecGatePolicy: Hashable, Sendable, Codable {
    /// Signing IDs that must not exec unless unlocked (or always-allowed).
    public var lockedSigningIDs: Set<String>

    /// Never deny these (FreshLock itself, optionally selected platform tools).
    public var alwaysAllowSigningIDs: Set<String>

    public init(
        lockedSigningIDs: Set<String> = [],
        alwaysAllowSigningIDs: Set<String> = ExecGatePolicy.defaultAlwaysAllow
    ) {
        self.lockedSigningIDs = lockedSigningIDs
        self.alwaysAllowSigningIDs = alwaysAllowSigningIDs
    }

    /// Host / helper signing ID used in production packaging.
    public static let freshLockSigningID = "gg.tame.freshlock"

    public static let defaultAlwaysAllow: Set<String> = [
        freshLockSigningID,
        "gg.tame.freshlock.helper",
        "gg.tame.freshlock.enforce"
    ]

    /// Build a policy from enabled protected-app bundle IDs.
    ///
    /// - Note: Assumes signing ID ≈ bundle identifier for modern apps. Helpers
    ///   and scripts need explicit entries; see docs/ENFORCEMENT.md.
    public static func fromProtectedBundleIDs(_ bundleIDs: Set<String>) -> ExecGatePolicy {
        ExecGatePolicy(lockedSigningIDs: bundleIDs)
    }
}

/// Pure evaluator — the same logic the ES client should call for AUTH_EXEC.
public struct ExecGateEvaluator: Sendable {
    public var policy: ExecGatePolicy
    public var allowlist: UnlockAllowlist

    public init(policy: ExecGatePolicy, allowlist: UnlockAllowlist = UnlockAllowlist()) {
        self.policy = policy
        self.allowlist = allowlist
    }

    public func decision(for identity: ProcessIdentity) -> ExecDecision {
        let id = identity.signingID
        if policy.alwaysAllowSigningIDs.contains(id) {
            return .allow
        }
        guard policy.lockedSigningIDs.contains(id) else {
            return .allow
        }
        if allowlist.allowedSigningIDs.contains(id) {
            return .allow
        }
        return .deny
    }
}
