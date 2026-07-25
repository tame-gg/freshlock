//
//  LockCoordinator+Outcomes.swift
//  FreshLockEngine
//
//  What happens once an authentication resolves: granting and scoping the
//  unlock, or counting the failure and deciding whether to keep asking.
//

import AppKit
import FreshLockCore

@MainActor
extension LockCoordinator {
    /// Route a finished LocalAuthentication attempt to the right outcome.
    func resolve(
        _ result: AuthResult,
        for app: ProtectedApp,
        config: Configuration,
        authenticatedPID: pid_t
    ) {
        switch result {
        case .success:
            grantAfterSuccess(app: app, config: config, authenticatedPID: authenticatedPID)
        case .cancelled:
            handleCancellation(app: app)
        case let .failure(error):
            if case .systemCancel = error {
                handleSystemCancel(app: app)
                return
            }
            handleFailure(app: app, config: config)
        }
    }

    /// Success only counts while the process we authenticated against - or a
    /// live sibling of the same bundle - is still around.
    private func grantAfterSuccess(app: ProtectedApp, config: Configuration, authenticatedPID: pid_t) {
        let bundleID = app.bundleIdentifier
        let livePIDs = ProtectedAppProcess.allPIDs(forBundleID: bundleID)
        let grantPID: pid_t? = livePIDs.contains(authenticatedPID)
            ? authenticatedPID
            : livePID(for: bundleID)
        guard let grantPID else {
            store.lock(bundleID)
            overlay.dismissOverlay(for: bundleID)
            visibility.stopKeeping(bundleID)
            Log.lifecycle.notice("Auth succeeded but process gone/replaced - not granting unlock")
            return
        }
        visibility.stopKeeping(bundleID)
        Log.lifecycle.info("Auth success for \(bundleID, privacy: .public) sessionPID=\(grantPID)")
        handleSuccess(app: app, config: config, pid: grantPID)
    }

    /// Internal cancel (switch-away / tear-down) versus the user pressing Cancel
    /// on the sheet. Either way the app stays locked; only the user's cancel
    /// leaves the overlay waiting for another explicit Unlock.
    private func handleCancellation(app: ProtectedApp) {
        let bundleID = app.bundleIdentifier
        if ignoreNextAuthCancel.remove(bundleID) != nil {
            visibility.stopKeeping(bundleID)
            store.lock(bundleID)
            if livePID(for: bundleID) == nil {
                overlay.dismissOverlay(for: bundleID)
            } else {
                overlay.pinCover(for: bundleID)
            }
            return
        }
        visibility.unhide(bundleID)
        visibility.startKeeping(bundleID)
        overlay.pinCover(for: bundleID)
        awaitingManualUnlock.insert(bundleID)
        Log.lifecycle.info("Auth cancelled for \(bundleID, privacy: .public) - overlay remains")
    }

    /// The system pulled the sheet, usually because focus moved. Keep the app
    /// covered; the budget decides whether the next poll may try again.
    private func handleSystemCancel(app: ProtectedApp) {
        let bundleID = app.bundleIdentifier
        visibility.unhide(bundleID)
        overlay.pinCover(for: bundleID)
        if !promptBudget.allowAutomaticPrompt(for: bundleID) {
            fallBackToManualUnlock(bundleID, reason: "system cancelled repeatedly")
        }
    }

    func handleSuccess(app: ProtectedApp, config: Configuration, pid: pid_t) {
        let bundleID = app.bundleIdentifier
        failureCounts[bundleID] = nil
        promptBudget.clearHistory(for: bundleID)
        let policy = app.effectiveRelockPolicy(default: config.settings.defaultRelockPolicy)
        let scope: UnlockScope = switch policy {
        case let .afterMinutes(m): .forDuration(TimeInterval(m * 60))
        case let .afterInactivity(m): .untilInactivity(TimeInterval(m * 60))
        case .everyLaunch, .manualOnly: .untilLogout
        default: .untilSleep
        }

        store.grantUnlock(bundleID, scope: scope, sessionPID: pid)
        startProcessPolling()
        visibility.stopKeeping(bundleID)
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

    func handleFailure(app: ProtectedApp, config _: Configuration) {
        let bundleID = app.bundleIdentifier
        let count = (failureCounts[bundleID] ?? 0) + 1
        failureCounts[bundleID] = count
        if let limit = app.terminateAfterFailures, count >= limit {
            visibility.stopKeeping(bundleID)
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            store.lock(bundleID)
            overlay.dismissOverlay(for: bundleID)
            securing.remove(bundleID)
            awaitingManualUnlock.remove(bundleID)
            failureCounts[bundleID] = nil
            promptBudget.clearHistory(for: bundleID)
        } else {
            visibility.unhide(bundleID)
            overlay.pinCover(for: bundleID)
            if !promptBudget.allowAutomaticPrompt(for: bundleID) {
                fallBackToManualUnlock(bundleID, reason: "authentication kept failing")
            }
        }
    }

    /// True when a live grant for this bundle is still inside the settings grace window.
    func isWithinGracePeriod(_ bundleID: String, config: Configuration) -> Bool {
        guard let grant = store.grants[bundleID], !grant.isTimeExpired() else { return false }
        return grant.isWithinGracePeriod(config.settings.gracePeriodSeconds)
    }
}
