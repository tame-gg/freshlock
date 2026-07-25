//
//  RelockManager.swift
//  AppLock
//
//  Translates system events into relock actions against the `UnlockStateStore`.
//  It observes sleep, wake, screen-lock and session events using public
//  notification centres (no polling), and revokes the unlock grants whose scope
//  or policy says they should end.
//

import AppKit
import AppLockCore
import Combine
import Foundation

@MainActor
final class RelockManager {
    private let store: UnlockStateStore
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(store: UnlockStateStore) {
        self.store = store
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        // System sleep → revoke "until sleep" grants and any lasting unlocks
        // whose policy is `.afterSleep`.
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSleep() }
        })

        // Fast user switching / session resignation behaves like a lock.
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSessionInactive() }
        })

        // Screen lock is delivered via the distributed notification centre.
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleScreenLock() }
        })

        Log.lifecycle.info("Relock manager started")
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.forEach(workspaceCenter.removeObserver)
        observers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers.removeAll()
    }

    // MARK: - Handlers

    private func handleSleep() {
        store.revokeGrants { scope in
            if case .untilSleep = scope { return true }
            return false
        }
        Log.lifecycle.debug("Revoked until-sleep grants on sleep")
    }

    private func handleScreenLock() {
        // Screen lock is a strong signal the user stepped away — clear
        // everything to be safe.
        store.lockAll()
    }

    private func handleSessionInactive() {
        store.revokeGrants { scope in
            if case .untilSleep = scope { return true }
            return false
        }
    }
}
