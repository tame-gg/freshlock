//
//  LockCoordinator+Commands.swift
//  FreshLockEngine
//
//  Commands the user issues directly rather than by switching apps: the global
//  lock/unlock shortcuts and menu-bar actions, and Quit from the lock overlay.
//  They share the coordinator's state but none of its event plumbing.
//

import AppKit
import FreshLockCore

@MainActor
extension LockCoordinator {
    func lockAllNow() {
        store.lockAll()
        let config = configProvider()
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier,
           let app = config.protectedApp(for: id), app.isEnabled
        {
            beginSecuring(app, config: config, pid: front.processIdentifier)
        }
        Log.lifecycle.info("Lock All")
    }

    func unlockAllNow() {
        authenticateAndGrantAll(scope: .untilSleep, reason: "unlock your protected apps")
    }

    /// Menu-bar / API path: require LocalAuthentication, then grant until sleep.
    func unlockUntilSleepNow() {
        authenticateAndGrantAll(scope: .untilSleep, reason: "unlock protected apps until sleep")
    }

    /// Menu-bar / API path: require LocalAuthentication, then grant until logout.
    func unlockUntilLogoutNow() {
        authenticateAndGrantAll(scope: .untilLogout, reason: "unlock protected apps until logout")
    }

    func authenticateAndGrantAll(scope: UnlockScope, reason: String) {
        let config = configProvider()
        Task { [weak self] in
            guard let self else { return }
            await armHostForTouchID()
            let result = await auth.authenticate(reason: reason)
            guard case .success = result else { return }
            var granted = 0
            for app in config.enabledProtectedApps {
                guard let pid = livePID(for: app.bundleIdentifier) else { continue }
                store.grantUnlock(app.bundleIdentifier, scope: scope, sessionPID: pid)
                overlay.dismissOverlay(for: app.bundleIdentifier)
                securing.remove(app.bundleIdentifier)
                awaitingManualUnlock.remove(app.bundleIdentifier)
                visibility.stopKeeping(app.bundleIdentifier)
                granted += 1
            }
            Log.lifecycle.info("Authenticated unlock (\(scope.displayName)) granted for \(granted) apps")
        }
    }

    /// User explicitly chose Quit on the lock overlay — terminate the protected app.
    func quitProtectedApp(app: ProtectedApp) {
        let bundleID = app.bundleIdentifier
        guard !closing.contains(bundleID) else { return }
        ignoreNextAuthCancel.insert(bundleID)
        auth.cancel()
        store.lock(bundleID)
        visibility.stopKeeping(bundleID)
        overlay.dismissOverlay(for: bundleID)
        authInFlight.remove(bundleID)
        securing.remove(bundleID)
        awaitingManualUnlock.remove(bundleID)
        closing.insert(bundleID)

        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        Log.lifecycle.info("Closing \(bundleID, privacy: .public) after quit")

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                where !app.isTerminated
            {
                app.forceTerminate()
            }
            closing.remove(bundleID)
            store.lock(bundleID)
        }
    }
}
