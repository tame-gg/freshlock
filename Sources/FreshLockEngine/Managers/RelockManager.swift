//
//  RelockManager.swift
//  FreshLock
//
//  Translates system events into relock actions against the `UnlockStateStore`.
//  It observes sleep, wake, screen-lock and session events using public
//  notification centres (no polling for those), and revokes unlock grants whose
//  scope or policy says they should end.
//
//  Idle (``.untilInactivity``) grants are checked on a light timer using
//  `CGEventSource` - real keyboard/mouse idle, not wall-clock time since unlock.
//

import AppKit
import CoreGraphics
import Foundation
import FreshLockCore

@MainActor
final class RelockManager {
    private let store: UnlockStateStore
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var inactivityTimer: Timer?

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

        startInactivityPolling()
        Log.lifecycle.info("Relock manager started")
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.forEach(workspaceCenter.removeObserver)
        observers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers.removeAll()
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    // MARK: - Handlers

    private func handleSleep() {
        store.revokeGrants { scope in
            if case .untilSleep = scope {
                return true
            }
            return false
        }
        Log.lifecycle.debug("Revoked until-sleep grants on sleep")
    }

    private func handleScreenLock() {
        // Walk-away signal: clear time-bounded and until-sleep grants. Keep
        // untilLogout (every-launch / manual-only) so those policies mean what
        // they say - only Lock All or process exit clears them.
        store.revokeGrants { scope in
            if case .untilLogout = scope {
                return false
            }
            return true
        }
        Log.lifecycle.debug("Revoked non-logout grants on screen lock")
    }

    private func handleSessionInactive() {
        store.revokeGrants { scope in
            if case .untilSleep = scope {
                return true
            }
            return false
        }
    }

    // MARK: - Real input inactivity

    private func startInactivityPolling() {
        inactivityTimer?.invalidate()
        // 5s is enough for minute-scale idle thresholds without measurable CPU.
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.revokeIdleGrants() }
        }
    }

    private func revokeIdleGrants() {
        let idle = SystemIdle.secondsSinceLastInput()
        store.revokeGrants { scope in
            guard let threshold = scope.inactivityThreshold else { return false }
            return idle >= threshold
        }
    }
}

/// System-wide seconds since the last keyboard or mouse event.
enum SystemIdle {
    /// `kCGAnyInputEventType` - any input in the combined session.
    private static let anyInput = CGEventType(rawValue: ~UInt32(0))!

    static func secondsSinceLastInput() -> CFTimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
