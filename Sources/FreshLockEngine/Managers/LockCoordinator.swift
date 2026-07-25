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
    let monitor: AppMonitorServiceProtocol
    let auth: AuthenticationServiceProtocol
    let overlay: OverlayServiceProtocol
    let accessibility: AccessibilityServiceProtocol
    let store: UnlockStateStore
    let configProvider: () -> Configuration

    private var cancellables = Set<AnyCancellable>()
    var failureCounts: [String: Int] = [:]
    private var lastFrontmostProtected: String?
    var authInFlight: Set<String> = []
    var closing: Set<String> = []
    var ignoreNextAuthCancel: Set<String> = []
    var securing: Set<String> = []
    /// Bundle IDs where the user cancelled the LA sheet; keep the overlay up
    /// without auto-reprompting until they tap Unlock or Quit.
    var awaitingManualUnlock: Set<String> = []
    /// Which Touch ID sheet is up, and how many automatic ones this app has had
    /// recently. The backstop that makes a prompt storm impossible.
    var promptBudget = AuthPromptBudget()
    /// Keeps secured apps out of the hidden state - a hidden app has no windows
    /// to cover.
    lazy var visibility = AppVisibilityKeeper { [weak self] bundleID in
        self?.runningApp(for: bundleID)
    }

    private var processPollTimer: Timer?

    /// Liveness poll cadence. Workspace launch/activate/terminate notifications
    /// are the fast path; this only has to catch what they miss, so it runs at a
    /// power-friendly interval and stops entirely when nothing is at stake.
    private static let processPollInterval: TimeInterval = 1.5

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
        reconcileDeadSessions()
        if !accessibility.isTrusted {
            Log.accessibility.notice("Accessibility not trusted — overlay uses CGWindowList fallback")
        }
        Log.lifecycle.info("Lock coordinator started")
    }

    /// Tear down every recurring source this coordinator owns.
    ///
    /// Without this the liveness poll outlived `LockEngine.stop()`, so a helper
    /// that had stood down for the GUI kept polling for the rest of the session.
    func stop() {
        cancellables.removeAll()
        stopProcessPolling()
        visibility.stopAll()
        securing.removeAll()
        authInFlight.removeAll()
        awaitingManualUnlock.removeAll()
        promptBudget.reset()
        Log.lifecycle.info("Lock coordinator stopped")
    }

    // MARK: - Dead-session reconciliation (root of quit→reauth)

    func startProcessPolling() {
        guard processPollTimer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.processPollInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileDeadSessions() }
        }
        // Generous tolerance lets the OS coalesce this with other wakeups.
        timer.tolerance = Self.processPollInterval * 0.5
        processPollTimer = timer
    }

    private func stopProcessPolling() {
        processPollTimer?.invalidate()
        processPollTimer = nil
    }

    /// Run the liveness poll only when something is actually at stake. With no
    /// protected app running and no lock UI in flight there is nothing for the
    /// poll to discover, and workspace notifications will restart it.
    private func updateProcessPolling(liveByBundle: [String: Set<pid_t>]) {
        let needed = !liveByBundle.isEmpty
            || !store.grants.isEmpty
            || !securing.isEmpty
            || !authInFlight.isEmpty
            || !awaitingManualUnlock.isEmpty
            || !closing.isEmpty
        if needed {
            startProcessPolling()
        } else {
            stopProcessPolling()
        }
    }

    /// Drop grants whose session PID is gone, then secure any frontmost locked app.
    private func reconcileDeadSessions() {
        let config = configProvider()
        let liveByBundle = ProtectedAppProcess.livePIDSets(
            forBundleIDs: config.enabledProtectedApps.map(\.bundleIdentifier)
        )
        defer { updateProcessPolling(liveByBundle: liveByBundle) }

        let revoked = store.revokeDeadSessions(livePIDsByBundle: liveByBundle)
        for bundleID in revoked {
            tearDownSessionUI(for: bundleID)
            Log.lifecycle.info("Revoked dead unlock session for \(bundleID, privacy: .public)")
        }

        // Nothing protected is running: no securing work is possible.
        guard !liveByBundle.isEmpty else { return }

        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for app in config.enabledProtectedApps {
            let bundleID = app.bundleIdentifier
            guard let livePIDs = liveByBundle[bundleID], !livePIDs.isEmpty else { continue }
            // Honor a grant bound to any still-live process for this bundle
            // (helpers share the bundle ID on Electron apps).
            if store.isUnlockedWhileAlive(bundleID, livePIDs: livePIDs) {
                continue
            }
            let isFront = frontID == bundleID
            let covering = overlay.isShowingOverlay(for: bundleID)
            guard isFront || covering else { continue }
            guard let running = ProtectedAppProcess.running(bundleID: bundleID) else { continue }
            beginSecuring(app, config: config, pid: running.processIdentifier)
        }
    }

    func livePID(for bundleID: String) -> pid_t? {
        ProtectedAppProcess.pid(forBundleID: bundleID)
    }

    func runningApp(for bundleID: String) -> NSRunningApplication? {
        ProtectedAppProcess.running(bundleID: bundleID)
    }

    private func tearDownSessionUI(for bundleID: String) {
        ignoreNextAuthCancel.insert(bundleID)
        if authInFlight.contains(bundleID) {
            auth.cancel()
        }
        authInFlight.remove(bundleID)
        promptBudget.clearPresented(for: bundleID)
        securing.remove(bundleID)
        closing.remove(bundleID)
        awaitingManualUnlock.remove(bundleID)
        promptBudget.clearHistory(for: bundleID)
        visibility.stopKeeping(bundleID)
        overlay.dismissOverlay(for: bundleID)
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
                        if case .afterSwitchingAway = policy {
                            return true
                        }
                        return false
                    }()
            if relockOnSwitchAway, !isWithinGracePeriod(previous, config: config) {
                store.lock(previous)
            }
            if securing.contains(previous) || overlay.isShowingOverlay(for: previous) {
                // A sheet raised moments ago is almost certainly being torn down
                // by the focus bounce that raising it caused, not by the user
                // switching apps. Leave it alone; they are reaching for it.
                let sheetIsProtected = authInFlight.contains(previous)
                    && promptBudget.isWithinCancelGrace(previous)
                if authInFlight.contains(previous), !sheetIsProtected {
                    ignoreNextAuthCancel.insert(previous)
                    auth.cancel()
                    authInFlight.remove(previous)
                }
                if !sheetIsProtected {
                    awaitingManualUnlock.remove(previous)
                    securing.remove(previous)
                }
                visibility.stopKeeping(previous)
                // Unpin rather than dismiss. Tearing the overlay down here left
                // a still-locked app permanently uncovered: any focus bounce
                // during the launch→auth handoff destroyed the cover, and the
                // in-flight guard in `beginSecuring` then refused to rebuild it.
                // Unpinned panels order out on their own while another app is
                // frontmost and come straight back when the user returns.
                overlay.unpinCover(for: previous)
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
        visibility.stopKeeping(bundleID)
    }

    func beginSecuring(_ app: ProtectedApp, config: Configuration, pid: pid_t) {
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
            visibility.startKeeping(bundleID)
            return
        }

        if authInFlight.contains(bundleID) || securing.contains(bundleID) {
            overlay.pinCover(for: bundleID)
            visibility.startKeeping(bundleID)
            return
        }

        store.lock(bundleID)
        securing.insert(bundleID)
        // Securing is exactly the state the liveness poll must cover; the next
        // reconcile tick stands it back down if it turns out to be unnecessary.
        startProcessPolling()
        Log.lifecycle.info("Securing \(bundleID, privacy: .public) pid \(pid)")
        Task { [weak self] in
            await self?.secureAndAuthenticate(app: app, config: config, pid: pid)
        }
    }

    private func secureAndAuthenticate(app: ProtectedApp, config: Configuration, pid _: pid_t) async {
        let bundleID = app.bundleIdentifier
        defer { securing.remove(bundleID) }

        visibility.startKeeping(bundleID)
        visibility.reveal(bundleID, activate: true)
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

        presentOverlay(for: app, config: config, pid: currentPID)

        if config.settings.notifyOnProtectedLaunch {
            NotificationPresenter.shared.notifyProtectedLaunch(appName: app.name)
        }

        _ = await overlay.waitUntilCovering(for: bundleID, timeout: .milliseconds(900))
        visibility.unhide(bundleID)
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

        // Auto-prompt off: leave the overlay up and wait for Unlock / Quit.
        // `awaitingManualUnlock` keeps the poll from re-entering this path.
        if !config.settings.automaticallyPromptAuthentication {
            awaitingManualUnlock.insert(bundleID)
            Log.lifecycle.info(
                "Auto-auth skipped for \(bundleID, privacy: .public) - awaiting Unlock"
            )
            return
        }

        await authenticate(app: app, config: config, pid: currentPID)
    }

    /// Raise the lock cover for `app`, wired to Unlock and Quit.
    private func presentOverlay(for app: ProtectedApp, config: Configuration, pid: pid_t) {
        let bundleID = app.bundleIdentifier
        let running = runningApp(for: bundleID)
        overlay.showOverlay(
            OverlayRequest(
                bundleID: bundleID,
                pid: pid,
                appName: app.name,
                icon: running?.icon ?? NSWorkspace.shared.icon(forFile: app.path),
                method: auth.availableMethod(),
                style: config.settings.overlayStyle,
                onUnlock: { [weak self] in
                    // Unlock always presents LA, even when auto-prompt is off or
                    // the automatic budget is spent - this is explicit intent.
                    guard let self, let livePID = livePID(for: bundleID) else { return }
                    awaitingManualUnlock.remove(bundleID)
                    let cfg = configProvider()
                    Task { [weak self] in
                        await self?.authenticate(app: app, config: cfg, pid: livePID, userInitiated: true)
                    }
                },
                onQuit: { [weak self] in self?.quitProtectedApp(app: app) }
            )
        )
        visibility.unhide(bundleID)
    }

    // MARK: - Visibility / LA

    /// Put FreshLock in front so LocalAuthentication's sheet has a host, while
    /// making sure the protected app does not get hidden in the shuffle.
    func armHostForTouchID(preserving bundleID: String? = nil) async {
        NSApp.activate(ignoringOtherApps: true)
        if let bundleID {
            visibility.unhide(bundleID)
        }
        await Task.yield()
        if let bundleID {
            visibility.unhide(bundleID)
        }
        try? await Task.sleep(for: .milliseconds(30))
        if let bundleID {
            visibility.unhide(bundleID)
        }
    }

    /// Stop asking and leave the overlay up with its Unlock button.
    func fallBackToManualUnlock(_ bundleID: String, reason: String) {
        awaitingManualUnlock.insert(bundleID)
        overlay.pinCover(for: bundleID)
        visibility.startKeeping(bundleID)
        Log.lifecycle.notice(
            "Auto-auth paused for \(bundleID, privacy: .public) - \(reason, privacy: .public)"
        )
    }

    private func authenticate(
        app: ProtectedApp,
        config: Configuration,
        pid: pid_t,
        userInitiated: Bool = false
    ) async {
        let bundleID = app.bundleIdentifier
        guard !authInFlight.contains(bundleID) else { return }

        if userInitiated {
            // The user pressed Unlock: honour it, and forget the earlier storm.
            promptBudget.clearHistory(for: bundleID)
        } else {
            // One system sheet at a time. A second request while another app's
            // sheet is up would cancel it out from under the user.
            if let presenting = promptBudget.presentingBundleID, presenting != bundleID {
                overlay.pinCover(for: bundleID)
                return
            }
            guard promptBudget.allowAutomaticPrompt(for: bundleID) else {
                fallBackToManualUnlock(bundleID, reason: "too many prompts, waiting for Unlock")
                return
            }
        }

        authInFlight.insert(bundleID)
        promptBudget.recordPresented(bundleID)
        defer {
            authInFlight.remove(bundleID)
            promptBudget.clearPresented(for: bundleID)
        }

        overlay.pinCover(for: bundleID)
        visibility.startKeeping(bundleID)
        await armHostForTouchID(preserving: bundleID)

        let result = await auth.authenticate(reason: "unlock \(app.name)")
        resolve(result, for: app, config: config, authenticatedPID: pid)
    }
}
