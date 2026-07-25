//
//  EnforcePolicySync.swift
//  FreshLockEngine
//
//  Bridges Phase 0 unlock grants + protected-app config into the on-disk state
//  the Phase 1 Endpoint Security client reads. Always safe to run: writing the
//  files does not activate kernel enforcement without an entitled sysext.
//

import Combine
import Foundation
import FreshLockCore
import FreshLockEnforce
import os.log

private let log = Logger(subsystem: "gg.tame.freshlock", category: "EnforcePolicySync")

/// Publishes locked signing IDs and unlock allowlist snapshots for the ES gate.
@MainActor
public final class EnforcePolicySync {
    private let unlockStore: UnlockStateStore
    private let configProvider: () -> Configuration
    private let allowlistStore: EnforceAllowlistStore
    private let lockedStore: EnforceLockedSetStore
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// Last state actually written to disk. Publishing is idempotent: identical
    /// state is never rewritten, which keeps grant churn off the filesystem.
    private var publishedLocked: Set<String>?
    private var publishedAllowed: Set<String>?
    /// Set while a coalesced publish is already queued for this runloop turn.
    private var publishQueued = false

    public init(
        unlockStore: UnlockStateStore,
        configProvider: @escaping () -> Configuration,
        allowlistStore: EnforceAllowlistStore = .defaultURL(),
        lockedStore: EnforceLockedSetStore = .defaultURL()
    ) {
        self.unlockStore = unlockStore
        self.configProvider = configProvider
        self.allowlistStore = allowlistStore
        self.lockedStore = lockedStore
    }

    /// Begin observing unlock grants. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        unlockStore.$grants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.publish()
            }
            .store(in: &cancellables)
        publishNow()
        log.info("Enforce policy sync started (writes allowlist/locked set for Phase 1)")
    }

    /// Push current locked set + unlock allowlist to disk.
    ///
    /// Coalesced: a burst of grant mutations (lock-all, dead-session sweeps)
    /// collapses into a single write at the end of the runloop turn.
    public func publish() {
        guard !publishQueued else { return }
        publishQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publishQueued = false
                self.publishNow()
            }
        }
    }

    /// Write the current state immediately, skipping files whose content is
    /// already up to date.
    public func publishNow() {
        let config = configProvider()
        let locked = Set(config.enabledProtectedApps.map(\.bundleIdentifier))
        let allowed = unlockStore.unlockedBundleIDs
        guard locked != publishedLocked || allowed != publishedAllowed else { return }
        do {
            if locked != publishedLocked {
                try lockedStore.save(locked)
                publishedLocked = locked
            }
            if allowed != publishedAllowed {
                try allowlistStore.save(UnlockAllowlist(allowedSigningIDs: allowed))
                publishedAllowed = allowed
            }
        } catch {
            log.error("Failed to publish enforce gate state: \(String(describing: error), privacy: .public)")
        }
    }

    /// Build the in-memory policy the ES client would use right now (for tests / UI).
    public func currentPolicy() -> ExecGatePolicy {
        ExecGatePolicy.fromProtectedBundleIDs(
            Set(configProvider().enabledProtectedApps.map(\.bundleIdentifier))
        )
    }

    public func currentAllowlist() -> UnlockAllowlist {
        UnlockAllowlist(allowedSigningIDs: unlockStore.unlockedBundleIDs)
    }
}
