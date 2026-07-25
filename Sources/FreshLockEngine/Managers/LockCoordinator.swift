//
//  LockCoordinator.swift
//  FreshLock
//
//  Lock-state lifecycle (security-critical):
//
//    Identity: bundle identifier is the persistent key for protection membership,
//    overlays, and unlock grants. PID is only a session token for "this launch".
//
//    launch/activate → no valid grant for *this PID* → overlay + Touch ID
//    auth success    → grantUnlock(sessionPID: livePID)
//    process exits   → revokeDeadSessions / terminate handler → grant cleared
//    next launch     → new PID → no grant → auth required again
//
//  `UnlockStateStore.revokeDeadSessions` is the authority: if the authenticated
//  process is not among the live PIDs for that bundle, the app is locked.
//  Workspace notifications are a fast path; the poll guarantees correctness
//  when notifications are missed.
//

import AppKit
import Combine
import Foundation
import FreshLockCore

@MainActor
final class LockCoordinator {
    private let monitor: AppMonitorServiceProtocol
    private let auth: AuthenticationServiceProtocol
    private let overlay: OverlayServiceProtocol
    private let accessibility: AccessibilityServiceProtocol
    private let store: UnlockStateStore
    private let configProvider: () -> Configuration

    private var cancellables = Set<AnyCancellable>()
    private var failureCounts: [String: Int] = [:]
    private var lastFrontmostProtected: String?
    private var authInFlight: Set<String> = []
    private var closing: Set<String> = []
    private var ignoreNextAuthCancel: Set<String> = []
    private var securing: Set<String> = []
    /// Bundle IDs where the user cancelled the LA sheet; keep the overlay up
    /// without auto-reprompting until they tap Unlock or Quit.
    private var awaitingManualUnlock: Set<String> = []
    private var visibilityKeepers: [String: Timer] = [:]
    private var processPollTimer: Timer?

    init(
        monitor: AppMonitorServiceProtocol,
        auth: AuthenticationServiceProtocol,
        overlay: OverlayServiceProtocol,
        accessibility: AccessibilityServiceProtocol,
        store: UnlockStateStore,
        configProvider: @escaping () -> Configuration
    ) {
        self.monitor = monitor
        self.auth = auth
        self.overlay = overlay
        self.accessibility = accessibility
        self.store = store
        self.configProvider = configProvider
    }

    func start() {
        monitor.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        monitor.start()
        startProcessPolling()
        reconcileDeadSessions()
        if !accessibility.isTrusted {
            Log.accessibility.notice("Accessibility not trusted — overlay uses CGWindowList fallback")
        }
        Log.lifecycle.info("Lock coordinator started")
    }

    // MARK: - Dead-session reconciliation (root of quit→reauth)

    private func startProcessPolling() {
        processPollTimer?.invalidate()
        processPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileDeadSessions() }
        }
    }

    /// Drop grants whose session PID is gone, then secure any frontmost locked app.
    private func reconcileDeadSessions() {
        let config = configProvider()
        let liveByBundle = ProtectedAppProcess.livePIDSets(
            forBundleIDs: config.enabledProtectedApps.map(\.bundleIdentifier)
        )

        let revoked = store.revokeDeadSessions(livePIDsByBundle: liveByBundle)
        for bundleID in revoked {
            tearDownSessionUI(for: bundleID)
            Log.lifecycle.info("Revoked dead unlock session for \(bundleID, privacy: .public)")
        }

        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for app in config.enabledProtectedApps {
            let bundleID = app.bundleIdentifier
            let livePIDs = liveByBundle[bundleID] ?? []
            // Honor a grant bound to any still-live process for this bundle
            // (helpers share the bundle ID on Electron apps).
            if store.isUnlockedWhileAlive(bundleID, livePIDs: livePIDs) {
                continue
            }
            guard let running = ProtectedAppProcess.running(bundleID: bundleID) else {
                continue
            }
            let pid = running.processIdentifier
            let isFront = frontID == bundleID
            let covering = overlay.isShowingOverlay(for: bundleID)
            if isFront || covering {
                beginSecuring(app, config: config, pid: pid)
            }
        }
    }

    private func livePID(for bundleID: String) -> pid_t? {
        ProtectedAppProcess.pid(forBundleID: bundleID)
    }

    private func runningApp(for bundleID: String) -> NSRunningApplication? {
        ProtectedAppProcess.running(bundleID: bundleID)
    }

    private func tearDownSessionUI(for bundleID: String) {
        ignoreNextAuthCancel.insert(bundleID)
        if authInFlight.contains(bundleID) {
            auth.cancel()
        }
        authInFlight.remove(bundleID)
        securing.remove(bundleID)
        closing.remove(bundleID)
        awaitingManualUnlock.remove(bundleID)
        stopKeepingVisible(bundleID)
        overlay.dismissOverlay(for: bundleID)
    }

    // MARK: - Shortcuts

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

    private func authenticateAndGrantAll(scope: UnlockScope, reason: String) {
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
                stopKeepingVisible(app.bundleIdentifier)
                granted += 1
            }
            Log.lifecycle.info("Authenticated unlock (\(scope.displayName)) granted for \(granted) apps")
        }
    }

    // MARK: - Events

    private func handle(_ event: AppLifecycleEvent) {
        reconcileDeadSessions()
        let config = configProvider()
        switch event {
        case let .launched(bundleID, pid):
            handleLaunch(bundleID: bundleID, pid: pid, config: config)
        case let .activated(bundleID, pid):
            handleActivation(bundleID: bundleID, pid: pid, config: config)
        case let .terminated(bundleID, pid):
            handleTermination(bundleID: bundleID, pid: pid)
        }
    }

    private func handleLaunch(bundleID: String, pid: pid_t, config: Configuration) {
        guard !FreshLockIdentity.transientFrontmostBundleIDs.contains(bundleID) else { return }
        // New process: clear any leftover grant for this bundle, then authenticate.
        store.lock(bundleID)
        guard let app = config.protectedApp(for: bundleID), app.isEnabled else { return }
        lastFrontmostProtected = bundleID
        Log.lifecycle.info("Launch \(bundleID, privacy: .public) pid \(pid) - requiring auth")
        beginSecuring(app, config: config, pid: pid)
    }

    private func handleActivation(bundleID: String, pid: pid_t, config: Configuration) {
        guard !FreshLockIdentity.transientFrontmostBundleIDs.contains(bundleID) else { return }
        guard !closing.contains(bundleID) else { return }
        enforceSwitchAway(newFrontmost: bundleID, config: config)
        guard let app = config.protectedApp(for: bundleID), app.isEnabled else { return }
        beginSecuring(app, config: config, pid: pid)
    }

    private func handleTermination(bundleID: String, pid: pid_t) {
        // Only clear the grant if it was bound to the process that just died
        // (another instance of the same bundle may still be alive).
        if store.grants[bundleID]?.sessionPID == pid {
            store.lock(bundleID)
        } else if ProtectedAppProcess.allPIDs(forBundleID: bundleID).isEmpty {
            store.lock(bundleID)
        }
        if ProtectedAppProcess.allPIDs(forBundleID: bundleID).isEmpty {
            tearDownSessionUI(for: bundleID)
            failureCounts[bundleID] = nil
        }
        Log.lifecycle.info("Terminated \(bundleID, privacy: .public) pid \(pid) - session checked")
    }
}

// MARK: - Switch-away / securing

@MainActor
extension LockCoordinator {
    private func enforceSwitchAway(newFrontmost bundleID: String, config: Configuration) {
        if FreshLockIdentity.transientFrontmostBundleIDs.contains(bundleID) {
            return
        }

        if let previous = lastFrontmostProtected, previous != bundleID,
           let prevApp = config.protectedApp(for: previous)
        {
            let policy = prevApp.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
            // Grace period softens focus flicker: skip switch-away relock briefly
            // after a successful unlock so apps that resign/regain focus don't
            // immediately re-prompt. `requireEveryLaunch` is paranoid mode:
            // always relock on switch-away (same as `.afterSwitchingAway`).
            let relockOnSwitchAway =
                config.settings.requireEveryLaunch
                || {
                    if case .afterSwitchingAway = policy { return true }
                    return false
                }()
            if relockOnSwitchAway, !isWithinGracePeriod(previous, config: config) {
                store.lock(previous)
            }
            if securing.contains(previous) || overlay.isShowingOverlay(for: previous) {
                if authInFlight.contains(previous) {
                    ignoreNextAuthCancel.insert(previous)
                    auth.cancel()
                    authInFlight.remove(previous)
                }
                awaitingManualUnlock.remove(previous)
                stopKeepingVisible(previous)
                overlay.dismissOverlay(for: previous)
                securing.remove(previous)
            }
        }

        if let app = config.protectedApp(for: bundleID), app.isEnabled {
            lastFrontmostProtected = bundleID
        } else if !FreshLockIdentity.transientFrontmostBundleIDs.contains(bundleID) {
            lastFrontmostProtected = nil
        }
    }

    // MARK: - Secure + auth

    private func clearSecuringUI(for bundleID: String, lock: Bool = true) {
        if lock {
            store.lock(bundleID)
        }
        awaitingManualUnlock.remove(bundleID)
        overlay.dismissOverlay(for: bundleID)
        stopKeepingVisible(bundleID)
    }

    private func beginSecuring(_ app: ProtectedApp, config: Configuration, pid: pid_t) {
        let bundleID = app.bundleIdentifier
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        let livePIDs = ProtectedAppProcess.allPIDs(forBundleID: bundleID)

        // A live grant always wins. Never wipe it here - that made
        // `requireEveryLaunch` destroy the grant on the success→activate path
        // and immediately re-prompt. Paranoid mode relocks on switch-away only.
        if policy.grantsLastingUnlock,
           store.isUnlocked(bundleID, pid: pid)
           || store.isUnlockedWhileAlive(bundleID, livePIDs: livePIDs)
        {
            Log.lifecycle.debug("Skip securing \(bundleID, privacy: .public) - live unlock grant")
            return
        }

        guard !closing.contains(bundleID) else { return }

        if awaitingManualUnlock.contains(bundleID) {
            overlay.pinCover(for: bundleID)
            startKeepingVisible(bundleID)
            return
        }

        if authInFlight.contains(bundleID) || securing.contains(bundleID) {
            overlay.pinCover(for: bundleID)
            startKeepingVisible(bundleID)
            return
        }

        store.lock(bundleID)
        securing.insert(bundleID)
        Log.lifecycle.info("Securing \(bundleID, privacy: .public) pid \(pid)")
        Task { [weak self] in
            await self?.secureAndAuthenticate(app: app, config: config, pid: pid)
        }
    }

    private func secureAndAuthenticate(app: ProtectedApp, config: Configuration, pid _: pid_t) async {
        let bundleID = app.bundleIdentifier
        defer { securing.remove(bundleID) }

        startKeepingVisible(bundleID)
        revealProtectedApp(bundleID: bundleID, activate: true)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        guard let currentPID = livePID(for: bundleID) else {
            clearSecuringUI(for: bundleID)
            return
        }

        let livePIDs = ProtectedAppProcess.allPIDs(forBundleID: bundleID)
        if store.isUnlocked(bundleID, pid: currentPID)
            || store.isUnlockedWhileAlive(bundleID, livePIDs: livePIDs)
        {
            clearSecuringUI(for: bundleID, lock: false)
            return
        }

        let running = runningApp(for: bundleID)
        let icon = running?.icon ?? NSWorkspace.shared.icon(forFile: app.path)

        overlay.showOverlay(
            OverlayRequest(
                bundleID: bundleID,
                pid: currentPID,
                appName: app.name,
                icon: icon,
                method: auth.availableMethod(),
                style: config.settings.overlayStyle,
                onUnlock: { [weak self] in
                    guard let self, let pid = livePID(for: bundleID) else { return }
                    awaitingManualUnlock.remove(bundleID)
                    beginSecuring(app, config: configProvider(), pid: pid)
                },
                onQuit: { [weak self] in self?.quitProtectedApp(app: app) }
            )
        )
        keepVisible(bundleID)

        if config.settings.notifyOnProtectedLaunch {
            NotificationPresenter.shared.notifyProtectedLaunch(appName: app.name)
        }

        _ = await overlay.waitUntilCovering(for: bundleID, timeout: .milliseconds(900))
        keepVisible(bundleID)
        try? await Task.sleep(for: .milliseconds(80))

        guard !closing.contains(bundleID) else { return }
        guard livePID(for: bundleID) != nil else {
            clearSecuringUI(for: bundleID)
            return
        }
        let liveNow = ProtectedAppProcess.allPIDs(forBundleID: bundleID)
        if store.isUnlocked(bundleID, pid: currentPID)
            || store.isUnlockedWhileAlive(bundleID, livePIDs: liveNow)
        {
            clearSecuringUI(for: bundleID, lock: false)
            return
        }

        await authenticate(app: app, config: config, pid: currentPID)
    }

    // MARK: - Visibility / LA

    private func startKeepingVisible(_ bundleID: String) {
        if visibilityKeepers[bundleID] == nil {
            visibilityKeepers[bundleID] = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepVisible(bundleID) }
            }
        }
        keepVisible(bundleID)
    }

    private func stopKeepingVisible(_ bundleID: String) {
        visibilityKeepers[bundleID]?.invalidate()
        visibilityKeepers[bundleID] = nil
    }

    private func keepVisible(_ bundleID: String) {
        guard let running = runningApp(for: bundleID) else { return }
        if running.isHidden {
            running.unhide()
        }
    }

    private func revealProtectedApp(bundleID: String, activate: Bool) {
        guard let running = runningApp(for: bundleID) else { return }
        if running.isHidden {
            running.unhide()
        }
        if activate {
            running.activate()
        }
    }

    private func armHostForTouchID(preserving bundleID: String? = nil) async {
        NSApp.activate(ignoringOtherApps: true)
        if let bundleID {
            keepVisible(bundleID)
        }
        await Task.yield()
        if let bundleID {
            keepVisible(bundleID)
        }
        try? await Task.sleep(for: .milliseconds(30))
        if let bundleID {
            keepVisible(bundleID)
        }
    }

    private func authenticate(app: ProtectedApp, config: Configuration, pid: pid_t) async {
        let bundleID = app.bundleIdentifier
        guard !authInFlight.contains(bundleID) else { return }
        authInFlight.insert(bundleID)
        defer { authInFlight.remove(bundleID) }

        overlay.pinCover(for: bundleID)
        startKeepingVisible(bundleID)
        await armHostForTouchID(preserving: bundleID)

        let result = await auth.authenticate(reason: "unlock \(app.name)")
        switch result {
        case .success:
            let livePIDs = ProtectedAppProcess.allPIDs(forBundleID: bundleID)
            // Prefer the PID we authenticated against if it is still alive;
            // otherwise fall back to any current live process for the bundle.
            let grantPID: pid_t?
            if livePIDs.contains(pid) {
                grantPID = pid
            } else {
                grantPID = livePID(for: bundleID)
            }
            guard let still = grantPID else {
                store.lock(bundleID)
                overlay.dismissOverlay(for: bundleID)
                stopKeepingVisible(bundleID)
                Log.lifecycle.notice("Auth succeeded but process gone/replaced - not granting unlock")
                return
            }
            stopKeepingVisible(bundleID)
            Log.lifecycle.info("Auth success for \(bundleID, privacy: .public) granting sessionPID=\(still)")
            handleSuccess(app: app, config: config, pid: still)
        case .cancelled:
            // Internal cancel (switch-away / tear-down): leave overlay pinned if the
            // process is still alive. User Cancel on the LA sheet: dismiss LA only
            // and keep the lock overlay so they can Unlock again or Quit explicitly.
            if ignoreNextAuthCancel.remove(bundleID) != nil {
                stopKeepingVisible(bundleID)
                store.lock(bundleID)
                if livePID(for: bundleID) == nil {
                    overlay.dismissOverlay(for: bundleID)
                } else {
                    overlay.pinCover(for: bundleID)
                }
                return
            }
            keepVisible(bundleID)
            startKeepingVisible(bundleID)
            overlay.pinCover(for: bundleID)
            awaitingManualUnlock.insert(bundleID)
            Log.lifecycle.info("Auth cancelled for \(bundleID, privacy: .public) — overlay remains")
        case let .failure(error):
            if case .systemCancel = error {
                keepVisible(bundleID)
                overlay.pinCover(for: bundleID)
                return
            }
            handleFailure(app: app, config: config)
        }
    }

    /// User explicitly chose Quit on the lock overlay — terminate the protected app.
    private func quitProtectedApp(app: ProtectedApp) {
        let bundleID = app.bundleIdentifier
        guard !closing.contains(bundleID) else { return }
        ignoreNextAuthCancel.insert(bundleID)
        auth.cancel()
        store.lock(bundleID)
        stopKeepingVisible(bundleID)
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

    private func handleSuccess(app: ProtectedApp, config: Configuration, pid: pid_t) {
        let bundleID = app.bundleIdentifier
        failureCounts[bundleID] = nil
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        let scope: UnlockScope = switch policy {
        case let .afterMinutes(m): .forDuration(TimeInterval(m * 60))
        case let .afterInactivity(m): .untilInactivity(TimeInterval(m * 60))
        case .everyLaunch, .manualOnly: .untilLogout
        default: .untilSleep
        }

        store.grantUnlock(bundleID, scope: scope, sessionPID: pid)
        stopKeepingVisible(bundleID)
        overlay.dismissOverlay(for: bundleID)
        securing.remove(bundleID)
        awaitingManualUnlock.remove(bundleID)

        if let running = runningApp(for: bundleID) {
            if running.isHidden {
                running.unhide()
            }
            running.activate()
        }
        Log.lifecycle.info("Granted unlock \(bundleID, privacy: .public) sessionPID=\(pid)")
    }

    private func handleFailure(app: ProtectedApp, config _: Configuration) {
        let bundleID = app.bundleIdentifier
        let count = (failureCounts[bundleID] ?? 0) + 1
        failureCounts[bundleID] = count
        if let limit = app.terminateAfterFailures, count >= limit {
            stopKeepingVisible(bundleID)
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            store.lock(bundleID)
            overlay.dismissOverlay(for: bundleID)
            securing.remove(bundleID)
            awaitingManualUnlock.remove(bundleID)
            failureCounts[bundleID] = nil
        } else {
            keepVisible(bundleID)
            overlay.pinCover(for: bundleID)
        }
    }

    /// True when a live grant for this bundle is still inside the settings grace window.
    private func isWithinGracePeriod(_ bundleID: String, config: Configuration) -> Bool {
        guard let grant = store.grants[bundleID], !grant.isTimeExpired() else { return false }
        return grant.isWithinGracePeriod(config.settings.gracePeriodSeconds)
    }
}
