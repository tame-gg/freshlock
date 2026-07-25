//
//  OverlayService.swift
//  FreshLockEngine
//
//  Owns the lock overlay windows. While a protected app is being secured the
//  overlay must cover its windows as soon as they exist — without waiting for
//  a Dock click, and without becoming key (which would fight Touch ID).
//
//  Covering policy while secured ("pinned"):
//  • Always cover the protected app's windows, even if frontmost briefly lags
//    behind launch (the previous frontmost-only gate caused the "click Dock
//    first" failure mode).
//  • Unpin / order out when the user activates a *different* non-transient app
//    so we do not float a cover over unrelated work.
//  • Re-pin when the protected app is activated again while still locked.
//
//  Panels are non-activating and sit at `.floating` — above app content, below
//  LocalAuthentication's system UI.
//

import AppKit
import FreshLockCore
import SwiftUI

/// Inputs for presenting a lock overlay over a protected app.
struct OverlayRequest {
    let bundleID: String
    let pid: pid_t
    let appName: String
    let icon: NSImage
    let method: AuthMethod
    let style: OverlayStyle
    let onUnlock: () -> Void
    let onQuit: () -> Void
}

@MainActor
protocol OverlayServiceProtocol: AnyObject {
    func isShowingOverlay(for bundleID: String) -> Bool
    /// True when at least one overlay panel is ordered in for this app.
    func isCovering(for bundleID: String) -> Bool
    func showOverlay(_ request: OverlayRequest)
    /// Wait until the overlay is covering real windows, or `timeout` elapses.
    func waitUntilCovering(for bundleID: String, timeout: Duration) async -> Bool
    /// Keep covering even when the protected app is not yet frontmost (launch).
    func pinCover(for bundleID: String)
    /// Stop forcing cover; panels order out if another app is frontmost.
    func unpinCover(for bundleID: String)
    func dismissOverlay(for bundleID: String)
    func dismissAll()
}

/// A borderless, non-activating panel. It intercepts mouse events over the
/// covered app but deliberately does **not** take key focus — stealing focus
/// fights Apple's Touch ID sheet and prevents authentication from completing.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class OverlayService: OverlayServiceProtocol {
    private let accessibility: AccessibilityServiceProtocol

    /// Cadence for the brief window right after an overlay is requested, while
    /// the protected app may not have created its windows yet. Covering fast
    /// here is security-critical.
    private static let settleInterval: TimeInterval = 0.1
    private static let settleDuration: TimeInterval = 1.5
    /// Steady-state backstop once the app has settled. With Accessibility
    /// trusted, AX notifications drive repositioning and this only catches what
    /// they miss; without it there are no events, so poll a little faster.
    private static let axBackstopInterval: TimeInterval = 1.0
    private static let unobservedBackstopInterval: TimeInterval = 0.5

    private var contentByBundleID: [String: LockOverlayView] = [:]
    private var pidByBundleID: [String: pid_t] = [:]
    private var windowsByBundleID: [String: [NSWindow]] = [:]
    private var trackTimers: [String: Timer] = [:]
    private var settleDeadlines: [String: Date] = [:]
    /// Frontmost PID at the last placement, so the cover is only re-raised when
    /// the window stack could actually have changed underneath it.
    private var lastFrontmostPID: [String: pid_t] = [:]
    /// Bundle IDs that must stay covered through the launch→auth handoff, even
    /// when `frontmostApplication` has not yet caught up to the protected app.
    private var pinnedBundleIDs: Set<String> = []
    /// Last known window frames per bundle — used when the process momentarily
    /// has no enumerable windows, instead of blanketing every display (which
    /// covered FreshLock's own picker UI).
    private var lastFramesByBundleID: [String: [NSRect]] = [:]
    /// Watches app switches so covers appear and disappear with the switch
    /// itself. Waiting for the backstop timer left a cover on screen for up to a
    /// second after the user moved to another app.
    private var activationObserver: NSObjectProtocol?

    init(accessibility: AccessibilityServiceProtocol) {
        self.accessibility = accessibility
    }

    private func installActivationObserverIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for bundleID in contentByBundleID.keys {
                    placeOrUpdate(bundleID)
                }
            }
        }
    }

    private func removeActivationObserverIfIdle() {
        guard contentByBundleID.isEmpty, let activationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    func isShowingOverlay(for bundleID: String) -> Bool {
        contentByBundleID[bundleID] != nil
    }

    func isCovering(for bundleID: String) -> Bool {
        guard let windows = windowsByBundleID[bundleID] else { return false }
        return windows.contains { $0.isVisible }
    }

    func showOverlay(_ request: OverlayRequest) {
        let bundleID = request.bundleID
        if contentByBundleID[bundleID] != nil {
            pinCover(for: bundleID)
            updateWatchedPID(bundleID: bundleID, pid: request.pid)
            placeOrUpdate(bundleID)
            return
        }

        contentByBundleID[bundleID] = LockOverlayView(
            appName: request.appName,
            icon: Image(nsImage: request.icon),
            method: request.method,
            style: request.style,
            onUnlock: request.onUnlock,
            onQuit: request.onQuit
        )
        pidByBundleID[bundleID] = request.pid
        pinnedBundleIDs.insert(bundleID)

        placeOrUpdate(bundleID)
        startTracking(bundleID)
        startWatchingPID(bundleID: bundleID, pid: request.pid)
        Log.overlay.info("Overlay engaged for \(bundleID, privacy: .public)")
    }

    /// Restart AX watching when the live process for a bundle changes (relaunch).
    private func updateWatchedPID(bundleID: String, pid: pid_t) {
        guard pid > 0 else { return }
        let previous = pidByBundleID[bundleID]
        guard previous != pid else { return }
        if let previous {
            accessibility.stopWatching(pid: previous)
        }
        pidByBundleID[bundleID] = pid
        startWatchingPID(bundleID: bundleID, pid: pid)
    }

    private func startWatchingPID(bundleID: String, pid: pid_t) {
        guard pid > 0 else { return }
        accessibility.startWatching(pid: pid) { [weak self] in
            self?.placeOrUpdate(bundleID)
        }
    }

    func waitUntilCovering(for bundleID: String, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if isCovering(for: bundleID) {
                return true
            }
            placeOrUpdate(bundleID)
            if isCovering(for: bundleID) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return isCovering(for: bundleID)
    }

    func pinCover(for bundleID: String) {
        pinnedBundleIDs.insert(bundleID)
        placeOrUpdate(bundleID)
    }

    func unpinCover(for bundleID: String) {
        pinnedBundleIDs.remove(bundleID)
        placeOrUpdate(bundleID)
    }

    func dismissOverlay(for bundleID: String) {
        stopTracking(bundleID)
        lastFrontmostPID[bundleID] = nil
        if let pid = pidByBundleID[bundleID] {
            accessibility.stopWatching(pid: pid)
        }
        windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }
        windowsByBundleID[bundleID] = nil
        contentByBundleID[bundleID] = nil
        pidByBundleID[bundleID] = nil
        lastFramesByBundleID[bundleID] = nil
        pinnedBundleIDs.remove(bundleID)
        Log.overlay.info("Overlay dismissed for \(bundleID, privacy: .public)")
    }

    func dismissAll() {
        for bundleID in Array(contentByBundleID.keys) {
            dismissOverlay(for: bundleID)
        }
    }

    // MARK: - Tracking

    private func placeOrUpdate(_ bundleID: String) {
        guard let content = contentByBundleID[bundleID], let pid = pidByBundleID[bundleID] else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        var windows = windowsByBundleID[bundleID] ?? []
        let covering = shouldCover(bundleID: bundleID, pid: pid, frontmost: frontmost)
        var frames = covering ? framesForPID(pid) : []

        if !frames.isEmpty {
            lastFramesByBundleID[bundleID] = frames
        } else if covering, pinnedBundleIDs.contains(bundleID) {
            // Prefer last known app frames over blanketing a display.
            frames = lastFramesByBundleID[bundleID] ?? []
        }

        // Last resort: the protected app owns the screen but exposes no
        // enumerable windows. That happens with no Accessibility trust, or when
        // its windows live on another Space (CGWindowList only reports the
        // active one). Leaving it uncovered means no protection at all, so cover
        // the displays — gated on the protected app actually being frontmost,
        // which is what previously made a blanket cover blank FreshLock's own UI.
        if frames.isEmpty, covering, let frontmost, frontmost.processIdentifier == pid {
            frames = NSScreen.screens.map(\.frame)
            Log.overlay.notice(
                "No window frames for \(bundleID, privacy: .public) — covering displays"
            )
        }

        guard !frames.isEmpty else {
            windows.forEach { $0.orderOut(nil) }
            lastFrontmostPID[bundleID] = nil
            return
        }

        // Only touch the window server when something actually moved. This runs
        // on a timer, and unconditional setFrame/orderFront churn was a large
        // share of idle CPU while an overlay was up.
        var changed = false
        if windows.count != frames.count {
            windows.forEach { $0.orderOut(nil) }
            windows = frames.map { Self.makeOverlayWindow(frame: $0, content: content) }
            windowsByBundleID[bundleID] = windows
            changed = true
        } else {
            for (window, frame) in zip(windows, frames) where window.frame != frame {
                window.setFrame(frame, display: true)
                changed = true
            }
        }

        // Re-raise when the stack could have shifted: geometry changed, a panel
        // is not on screen, or a different app came forward.
        let frontPID = frontmost?.processIdentifier
        if changed || lastFrontmostPID[bundleID] != frontPID || windows.contains(where: { !$0.isVisible }) {
            // Order front WITHOUT becoming key, so LocalAuthentication keeps focus.
            windows.forEach { $0.orderFrontRegardless() }
        }
        lastFrontmostPID[bundleID] = frontPID
    }

    private func framesForPID(_ pid: pid_t) -> [NSRect] {
        let axFrames = accessibility.windowFrames(pid: pid)
        if !axFrames.isEmpty {
            return axFrames
        }
        return Self.cgWindowFrames(pid: pid)
    }

    private func startTracking(_ bundleID: String) {
        settleDeadlines[bundleID] = Date().addingTimeInterval(Self.settleDuration)
        scheduleTracking(bundleID, interval: Self.settleInterval)
    }

    private var backstopInterval: TimeInterval {
        accessibility.isTrusted ? Self.axBackstopInterval : Self.unobservedBackstopInterval
    }

    private func scheduleTracking(_ bundleID: String, interval: TimeInterval) {
        trackTimers[bundleID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.trackingTick(bundleID, interval: interval)
            }
        }
        timer.tolerance = interval * 0.3
        trackTimers[bundleID] = timer
    }

    private func trackingTick(_ bundleID: String, interval: TimeInterval) {
        guard contentByBundleID[bundleID] != nil else {
            stopTracking(bundleID)
            return
        }
        placeOrUpdate(bundleID)

        // Once the app's windows have settled, drop to the backstop cadence and
        // let AX notifications carry subsequent moves/resizes.
        guard interval == Self.settleInterval else { return }
        if let deadline = settleDeadlines[bundleID], Date() >= deadline {
            settleDeadlines[bundleID] = nil
            scheduleTracking(bundleID, interval: backstopInterval)
        }
    }

    private func stopTracking(_ bundleID: String) {
        trackTimers[bundleID]?.invalidate()
        trackTimers[bundleID] = nil
        settleDeadlines[bundleID] = nil
    }

    /// Whether the cover for `bundleID` belongs on screen right now.
    ///
    /// The panel sits at `.floating`, above every ordinary window, so it is only
    /// ever safe while the app it is sized to owns the screen. Being pinned used
    /// to force covering regardless of who was frontmost, which meant a locked
    /// app's blur hung over whatever the user switched to - a Discord-shaped
    /// panel floating on top of the editor they had tabbed into. Pinning now
    /// only decides what to do when there is no frontmost app to consult.
    private func shouldCover(bundleID: String, pid: pid_t, frontmost: NSRunningApplication?) -> Bool {
        guard let frontmost else { return pinnedBundleIDs.contains(bundleID) }

        if let id = frontmost.bundleIdentifier {
            // FreshLock's own windows must never end up underneath a cover.
            if FreshLockIdentity.hostBundleIDs.contains(id) {
                return false
            }
            // Our Touch ID sheet is up: hold the app covered behind it.
            if FreshLockIdentity.authUIBundleIDs.contains(id) {
                return contentByBundleID[bundleID] != nil
            }
        }

        if frontmost.processIdentifier == pid {
            return true
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.isActive {
            return true
        }
        // Someone else's work is in front. Whatever the protected app is
        // showing is behind their windows; floating a cover over it would put
        // the blur on top of them instead.
        return false
    }

    // MARK: - Window geometry (CG fallback)

    private static func cgWindowFrames(pid: pid_t) -> [NSRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var frames: [NSRect] = []
        for info in infoList {
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            guard bounds.width >= 80, bounds.height >= 80 else { continue }

            let cocoaY = primaryHeight - bounds.origin.y - bounds.height
            frames.append(NSRect(x: bounds.origin.x, y: cocoaY, width: bounds.width, height: bounds.height))
        }
        return frames
    }

    private static func makeOverlayWindow(frame: NSRect, content: LockOverlayView) -> NSWindow {
        let window = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        window.contentView = hosting
        window.setFrame(frame, display: true)
        // Above ordinary app windows, below LocalAuthentication system UI.
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Mouse is fine on the cover; never take keyboard / key status from LA.
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.orderFrontRegardless()
        return window
    }
}
