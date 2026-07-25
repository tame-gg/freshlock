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
    /// Bundle IDs being closed after a cancelled auth. Their activation events
    /// are ignored so cancelling doesn't immediately re-lock and re-prompt while
    /// the app is quitting.
    private var closing: Set<String> = []

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

    /// Protected apps we have hidden (`NSRunningApplication.hide`) because they
    /// are locked and in the background. Tracked so we only ever reveal apps we
    /// hid, never ones the user hid themselves.
    private var hiddenByUs: Set<String> = []
    /// Active only while apps are hidden; re-hides any that reveal themselves.
    private var rehideTimer: Timer?

    func start() {
        monitor.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        // Relocks that don't come from app switching (sleep, screen lock, timer
        // expiry, Lock All) change the store directly — reconcile hidden state
        // when it does, so backgrounded apps that just locked get hidden.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.reconcileHiddenApps() } }
            .store(in: &cancellables)
        monitor.start()
        Log.lifecycle.info("Lock coordinator started")
    }

    /// Hide protected apps that are locked and backgrounded, and reveal ones we
    /// hid once they're unlocked. This is what keeps a locked app's content out
    /// of Mission Control, Spaces, App Exposé and Stage Manager — macOS offers
    /// no public way to exclude another app's window from those snapshots, so
    /// the only option is to hide the app's windows entirely while it's locked.
    private func reconcileHiddenApps() {
        let config = configProvider()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        for app in config.protectedApps where app.isEnabled {
            let bundleID = app.bundleIdentifier
            guard let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first else {
                hiddenByUs.remove(bundleID)
                continue
            }
            let isFrontmost = running.processIdentifier == frontPID

            if store.isUnlocked(bundleID) {
                // Unlocked: reveal it if we were the ones who hid it.
                if hiddenByUs.remove(bundleID) != nil { running.unhide() }
            } else if isFrontmost || closing.contains(bundleID) {
                // Locked but currently the active app (the overlay covers it) or
                // being closed after a cancel: don't hide.
                hiddenByUs.remove(bundleID)
            } else {
                // Locked and in the background: hide so it can't be previewed.
                if !running.isHidden { running.hide() }
                hiddenByUs.insert(bundleID)
            }
        }
        updateRehideTimer()
    }

    /// While any app is hidden, re-run reconciliation on a short interval. A
    /// background app can *reveal itself* when it finishes creating its first
    /// window (e.g. shortly after a background launch), and that doesn't fire any
    /// app-activation event we could react to — so this safety net re-hides it
    /// promptly. The timer stops as soon as nothing is hidden, keeping idle CPU
    /// at zero.
    private func updateRehideTimer() {
        if hiddenByUs.isEmpty {
            rehideTimer?.invalidate()
            rehideTimer = nil
        } else if rehideTimer == nil {
            rehideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcileHiddenApps() }
            }
        }
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

    /// Apps whose activation is a *transient* side effect of locking, not a real
    /// user app-switch: Apple's Touch ID sheet and AppLock itself. Treating them
    /// as switches would forget which app was protected and break switch-away
    /// relocking.
    private static let transientBundleIDs: Set<String> = [
        "com.apple.LocalAuthentication.UIAgent",
        "gg.tame.applock"
    ]

    private func handle(_ event: AppLifecycleEvent) {
        let config = configProvider()
        switch event {
        case .launched(let bundleID, _), .activated(let bundleID, _):
            guard !Self.transientBundleIDs.contains(bundleID) else { return }
            guard !closing.contains(bundleID) else { return }
            enforceSwitchAway(newFrontmost: bundleID, config: config)
            guard let app = config.protectedApp(for: bundleID), app.isEnabled else { return }
            lockIfNeeded(app, config: config)
        case .terminated(let bundleID):
            overlay.dismissOverlay(for: bundleID)
            authInFlight.remove(bundleID)
            closing.remove(bundleID)
            hiddenByUs.remove(bundleID)
            failureCounts[bundleID] = nil
            // Relock on quit so the next launch always re-authenticates. This is
            // what makes `.everyLaunch` mean "once per launch".
            store.lock(bundleID)
        }
        // After any app event, re-hide backgrounded locked apps / reveal unlocked
        // ones so previews never show protected content.
        reconcileHiddenApps()
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

    /// Present the overlay + auth if the app is currently locked *and* frontmost.
    ///
    /// A locked app that is **not** frontmost (e.g. it launched in the
    /// background, on another Space, or on another display) is protected by
    /// hiding it (`reconcileHiddenApps`) rather than prompting — so it can never
    /// be seen or previewed unauthenticated, and we don't pop a Touch ID sheet
    /// for an app the user hasn't opened. The overlay + prompt appear the moment
    /// they focus it, which fires another activation event.
    private func lockIfNeeded(_ app: ProtectedApp, config: Configuration) {
        let bundleID = app.bundleIdentifier
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        let mustAlwaysAuth = config.settings.requireEveryLaunch || !policy.grantsLastingUnlock

        if !mustAlwaysAuth && store.isUnlocked(bundleID) { return }
        guard !overlay.isShowingOverlay(for: bundleID) else { return }
        guard !authInFlight.contains(bundleID) else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }

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
        guard !closing.contains(bundleID) else { return }
        // Dismiss Apple's Touch ID sheet if it's still up (e.g. the user tapped
        // the overlay's Cancel button rather than the sheet's).
        auth.cancel()
        store.lock(bundleID)
        overlay.dismissOverlay(for: bundleID)
        authInFlight.remove(bundleID)
        // Ignore this app's activations while it quits, so the app re-becoming
        // frontmost as the sheet closes doesn't immediately re-lock and re-prompt.
        closing.insert(bundleID)

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        Log.lifecycle.info("Closing \(bundleID, privacy: .public) after cancel")

        // Escalate to force-quit anything that ignored the polite request, then
        // stop ignoring the app: if it somehow survived, protection resumes.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where !app.isTerminated {
                app.forceTerminate()
            }
            self.closing.remove(bundleID)
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
        // `.everyLaunch` stays unlocked until the app quits; the `.terminated`
        // handler revokes the grant so the next launch re-prompts.
        case .everyLaunch: scope = .untilLogout
        default: scope = .untilSleep
        }
        store.grantUnlock(bundleID, scope: scope)
        overlay.dismissOverlay(for: bundleID)
        // Reveal and bring the app forward (it may have been hidden while locked).
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.unhide()
            running.activate()
        }
        hiddenByUs.remove(bundleID)
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
