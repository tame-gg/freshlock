//
//  LockCoordinator.swift
//  AppLock
//
//  The brain of AppLock. It wires the app monitor, authentication, overlay and
//  unlock state together into the lock/unlock flow:
//
//    launch/activate → is it protected & locked? → cover with overlay →
//    present Apple's auth sheet → on success unlock & remove overlay;
//    on failure keep the overlay (and optionally terminate after N failures).
//
//  It also enforces the `.afterSwitchingAway` relock policy by watching which
//  app is frontmost.
//

import AppKit
import AppLockCore
import Combine
import Foundation

@MainActor
final class LockCoordinator {
    private let monitor: AppMonitorServiceProtocol
    private let auth: AuthenticationServiceProtocol
    private let overlay: OverlayServiceProtocol
    private let store: UnlockStateStore
    private let configProvider: () -> Configuration

    private var cancellables = Set<AnyCancellable>()
    /// Consecutive failed attempts per app, for the terminate-after-N feature.
    private var failureCounts: [String: Int] = [:]
    /// The last protected app that was frontmost, for `.afterSwitchingAway`.
    private var lastFrontmostProtected: String?
    /// Bundle IDs with an in-flight auth prompt, to avoid double-prompting.
    private var authInFlight: Set<String> = []

    init(
        monitor: AppMonitorServiceProtocol,
        auth: AuthenticationServiceProtocol,
        overlay: OverlayServiceProtocol,
        store: UnlockStateStore,
        configProvider: @escaping () -> Configuration
    ) {
        self.monitor = monitor
        self.auth = auth
        self.overlay = overlay
        self.store = store
        self.configProvider = configProvider
    }

    func start() {
        monitor.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        monitor.start()
        Log.lifecycle.info("Lock coordinator started")
    }

    // MARK: - Global-shortcut actions

    /// Relock every unlocked app immediately, and re-cover the frontmost
    /// protected app so the lock takes visible effect right away.
    func lockAllNow() {
        store.lockAll()
        let config = configProvider()
        if let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let app = config.protectedApp(for: frontID), app.isEnabled {
            presentLock(for: app, config: config)
        }
        Log.lifecycle.info("Lock All triggered via shortcut")
    }

    /// Authenticate once and grant an until-sleep unlock to every enabled app,
    /// dismissing any visible overlays on success.
    func unlockAllNow() {
        let config = configProvider()
        Task { [weak self] in
            guard let self else { return }
            let result = await auth.authenticate(reason: "unlock your protected apps")
            guard case .success = result else { return }
            for app in config.enabledProtectedApps {
                store.grantUnlock(app.bundleIdentifier, scope: .untilSleep)
                overlay.dismissOverlay(for: app.bundleIdentifier)
            }
            Log.lifecycle.info("Unlock All granted via shortcut")
        }
    }

    // MARK: - Event handling

    private func handle(_ event: AppLifecycleEvent) {
        let config = configProvider()
        switch event {
        case .launched(let bundleID, _), .activated(let bundleID, _):
            enforceSwitchAway(newFrontmost: bundleID, config: config)
            guard let app = config.protectedApp(for: bundleID), app.isEnabled else { return }
            lockIfNeeded(app, config: config)
        case .terminated(let bundleID):
            overlay.dismissOverlay(for: bundleID)
            authInFlight.remove(bundleID)
            // A terminated app relocks unless it holds a lasting grant.
            failureCounts[bundleID] = nil
        }
    }

    /// If the newly-frontmost app differs from a protected app that used the
    /// `.afterSwitchingAway` policy, relock that previous app.
    private func enforceSwitchAway(newFrontmost bundleID: String, config: Configuration) {
        if let previous = lastFrontmostProtected, previous != bundleID,
           let prevApp = config.protectedApp(for: previous) {
            let policy = prevApp.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
            if case .afterSwitchingAway = policy {
                store.lock(previous)
                Log.lifecycle.debug("Relocked \(previous, privacy: .public) on switch-away")
            }
        }
        if let app = config.protectedApp(for: bundleID), app.isEnabled {
            lastFrontmostProtected = bundleID
        } else {
            lastFrontmostProtected = nil
        }
    }

    /// Present the overlay + auth if the app is currently locked.
    private func lockIfNeeded(_ app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        let mustAlwaysAuth = config.settings.requireEveryLaunch || !policy.grantsLastingUnlock

        if !mustAlwaysAuth && store.isUnlocked(bundleID) { return }
        guard !overlay.isShowingOverlay(for: bundleID) else { return }
        guard !authInFlight.contains(bundleID) else { return }

        presentLock(for: app, config: config)
    }

    private func presentLock(for app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let icon = running?.icon ?? NSWorkspace.shared.icon(forFile: app.path)
        let pid = running?.processIdentifier ?? -1

        overlay.showOverlay(
            for: bundleID,
            pid: pid,
            appName: app.name,
            icon: icon,
            method: auth.availableMethod(),
            style: config.settings.overlayStyle,
            onUnlock: { [weak self] in self?.authenticate(app: app, config: config) },
            onCancel: { [weak self] in self?.cancelAndClose(app: app) }
        )

        if config.settings.notifyOnProtectedLaunch {
            NotificationPresenter.shared.notifyProtectedLaunch(appName: app.name)
        }

        // Kick off authentication immediately; the overlay is the fallback UI
        // if the user cancels.
        authenticate(app: app, config: config)
    }

    private func authenticate(app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        guard !authInFlight.contains(bundleID) else { return }
        authInFlight.insert(bundleID)

        Task { [weak self] in
            guard let self else { return }
            let result = await auth.authenticate(reason: "unlock \(app.name)")
            self.authInFlight.remove(bundleID)
            switch result {
            case .success:
                self.handleSuccess(app: app, config: config)
            case .cancelled:
                // Cancelling authentication closes the app entirely.
                self.cancelAndClose(app: app)
            case .failure:
                self.handleFailure(app: app, config: config)
            }
        }
    }

    /// The user declined to authenticate: relock, remove the overlay, and quit
    /// the protected app. We ask politely first (`terminate`, which lets the app
    /// save/prompt) and escalate to a force terminate if it's still running
    /// shortly after.
    private func cancelAndClose(app: ProtectedApp) {
        let bundleID = app.bundleIdentifier
        store.lock(bundleID)
        overlay.dismissOverlay(for: bundleID)
        authInFlight.remove(bundleID)

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        Log.lifecycle.info("Closing \(bundleID, privacy: .public) after cancel")

        // Escalate to force-quit anything that ignored the polite request.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard self != nil else { return }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where !app.isTerminated {
                app.forceTerminate()
            }
        }
    }

    private func handleSuccess(app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        failureCounts[bundleID] = nil
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        // Translate the standing relock policy into a concrete grant lifetime.
        let scope: UnlockScope
        switch policy {
        case .afterMinutes(let m): scope = .forDuration(TimeInterval(m * 60))
        case .afterInactivity(let m): scope = .forDuration(TimeInterval(m * 60))
        case .everyLaunch: scope = .forDuration(0) // effectively immediate relock
        default: scope = .untilSleep
        }
        if policy.grantsLastingUnlock {
            store.grantUnlock(bundleID, scope: scope)
        }
        overlay.dismissOverlay(for: bundleID)
    }

    private func handleFailure(app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        let count = (failureCounts[bundleID] ?? 0) + 1
        failureCounts[bundleID] = count
        Log.auth.notice("Auth failure #\(count) for \(bundleID, privacy: .public)")

        if let limit = app.terminateAfterFailures, count >= limit {
            terminate(bundleID: bundleID)
        }
        // Otherwise the overlay stays; the user retries from the Unlock button.
    }

    private func terminate(bundleID: String) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            running.terminate()
        }
        overlay.dismissOverlay(for: bundleID)
        failureCounts[bundleID] = nil
        Log.auth.warning("Terminated \(bundleID, privacy: .public) after repeated failures")
    }
}
