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

@MainActor
protocol OverlayServiceProtocol: AnyObject {
    func isShowingOverlay(for bundleID: String) -> Bool
    /// True when at least one overlay panel is ordered in for this app.
    func isCovering(for bundleID: String) -> Bool
    func showOverlay(
        for bundleID: String,
        pid: pid_t,
        appName: String,
        icon: NSImage,
        method: AuthMethod,
        style: OverlayStyle,
        onUnlock: @escaping () -> Void,
        onCancel: @escaping () -> Void
    )
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
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayService: OverlayServiceProtocol {
    private let accessibility: AccessibilityServiceProtocol

    private var contentByBundleID: [String: LockOverlayView] = [:]
    private var pidByBundleID: [String: pid_t] = [:]
    private var windowsByBundleID: [String: [NSWindow]] = [:]
    private var trackTimers: [String: Timer] = [:]
    /// Bundle IDs that must stay covered through the launch→auth handoff, even
    /// when `frontmostApplication` has not yet caught up to the protected app.
    private var pinnedBundleIDs: Set<String> = []
    /// Last known window frames per bundle — used when the process momentarily
    /// has no enumerable windows, instead of blanketing every display (which
    /// covered FreshLock's own picker UI).
    private var lastFramesByBundleID: [String: [NSRect]] = [:]

    init(accessibility: AccessibilityServiceProtocol) {
        self.accessibility = accessibility
    }

    func isShowingOverlay(for bundleID: String) -> Bool {
        contentByBundleID[bundleID] != nil
    }

    func isCovering(for bundleID: String) -> Bool {
        guard let windows = windowsByBundleID[bundleID] else { return false }
        return windows.contains { $0.isVisible }
    }

    func showOverlay(
        for bundleID: String,
        pid: pid_t,
        appName: String,
        icon: NSImage,
        method: AuthMethod,
        style: OverlayStyle,
        onUnlock: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        if contentByBundleID[bundleID] != nil {
            pinCover(for: bundleID)
            updateWatchedPID(bundleID: bundleID, pid: pid)
            placeOrUpdate(bundleID)
            return
        }

        contentByBundleID[bundleID] = LockOverlayView(
            appName: appName,
            icon: Image(nsImage: icon),
            method: method,
            style: style,
            onUnlock: onUnlock,
            onCancel: onCancel
        )
        pidByBundleID[bundleID] = pid
        pinnedBundleIDs.insert(bundleID)

        placeOrUpdate(bundleID)
        startTracking(bundleID)
        startWatchingPID(bundleID: bundleID, pid: pid)
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
            if isCovering(for: bundleID) { return true }
            placeOrUpdate(bundleID)
            if isCovering(for: bundleID) { return true }
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
        trackTimers[bundleID]?.invalidate()
        trackTimers[bundleID] = nil
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

        var windows = windowsByBundleID[bundleID] ?? []
        var frames = shouldCover(bundleID: bundleID, pid: pid) ? framesForPID(pid) : []

        if !frames.isEmpty {
            lastFramesByBundleID[bundleID] = frames
        } else if pinnedBundleIDs.contains(bundleID), shouldCover(bundleID: bundleID, pid: pid) {
            // Prefer last known app frames. Never fall back to full-screen —
            // that blanketed FreshLock / other apps and made the picker look empty.
            frames = lastFramesByBundleID[bundleID] ?? []
        }

        guard !frames.isEmpty else {
            windows.forEach { $0.orderOut(nil) }
            return
        }

        if windows.count != frames.count {
            windows.forEach { $0.orderOut(nil) }
            windows = frames.map { Self.makeOverlayWindow(frame: $0, content: content) }
            windowsByBundleID[bundleID] = windows
        } else {
            for (window, frame) in zip(windows, frames) where window.frame != frame {
                window.setFrame(frame, display: true)
            }
        }
        // Order front WITHOUT becoming key, so LocalAuthentication keeps focus.
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func framesForPID(_ pid: pid_t) -> [NSRect] {
        let axFrames = accessibility.windowFrames(pid: pid)
        if !axFrames.isEmpty { return axFrames }
        return Self.cgWindowFrames(pid: pid)
    }

    private func startTracking(_ bundleID: String) {
        trackTimers[bundleID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                guard self.contentByBundleID[bundleID] != nil else {
                    self.trackTimers[bundleID]?.invalidate()
                    self.trackTimers[bundleID] = nil
                    return
                }
                self.placeOrUpdate(bundleID)
            }
        }
        trackTimers[bundleID] = timer
    }

    /// Cover when pinned (launch→auth), when the protected app is frontmost /
    /// active, or when LocalAuthentication is frontmost.
    /// When *FreshLock itself* is frontmost, never cover — full-screen / pinned
    /// covers were blanking the application picker.
    private func shouldCover(bundleID: String, pid: pid_t) -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier {
            if id == FreshLockIdentity.mainBundleID || id == FreshLockIdentity.helperBundleID {
                return false
            }
            if id == FreshLockIdentity.localAuthUIAgent {
                return contentByBundleID[bundleID] != nil
            }
        }
        if pinnedBundleIDs.contains(bundleID) { return true }
        guard let front = NSWorkspace.shared.frontmostApplication else { return true }
        if front.processIdentifier == pid { return true }
        if let app = NSRunningApplication(processIdentifier: pid), app.isActive { return true }
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
