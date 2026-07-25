//
//  OverlayService.swift
//  AppLockEngine
//
//  Owns the lock overlay windows. The overlay must cover the *whole protected
//  app* and leave it completely non-interactable until the user authenticates,
//  even as they try to move, resize or minimise it. We achieve this by:
//
//  • Continuously tracking the app's on-screen window frames (a lightweight
//    timer) and matching an overlay panel to each — so the cover follows resize
//    and move in real time. The overlay is inset slightly *larger* than the
//    window so the resize edges are covered too.
//  • Making the overlay a key window and activating AppLock, so keyboard input
//    goes to the (inert) overlay rather than the app underneath.
//  • Intercepting mouse events over the covered region (including the title bar,
//    which is inside the window bounds), so clicks and drags do nothing.
//
//  There is deliberately no full-screen fallback: the overlay appears the moment
//  the app's window exists, avoiding the jarring "full screen then shrink"
//  flash. Authentication (the system Touch ID sheet) is the real gate and runs
//  regardless of overlay timing.
//

import AppKit
import AppLockCore
import SwiftUI

@MainActor
protocol OverlayServiceProtocol: AnyObject {
    func isShowingOverlay(for bundleID: String) -> Bool
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
    private var contentByBundleID: [String: LockOverlayView] = [:]
    private var pidByBundleID: [String: pid_t] = [:]
    private var windowsByBundleID: [String: [NSWindow]] = [:]
    private var trackTimers: [String: Timer] = [:]

    /// How much larger than the window to draw the cover, so resize edges (which
    /// sit a few points outside the reported bounds) are also blocked.
    private static let outset: CGFloat = 6

    func isShowingOverlay(for bundleID: String) -> Bool {
        contentByBundleID[bundleID] != nil
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
        guard contentByBundleID[bundleID] == nil else { return }

        contentByBundleID[bundleID] = LockOverlayView(
            appName: appName,
            icon: Image(nsImage: icon),
            method: method,
            style: style,
            onUnlock: onUnlock,
            onCancel: onCancel
        )
        pidByBundleID[bundleID] = pid

        placeOrUpdate(bundleID)
        startTracking(bundleID)
        Log.overlay.info("Overlay engaged for \(bundleID, privacy: .public)")
    }

    func dismissOverlay(for bundleID: String) {
        trackTimers[bundleID]?.invalidate()
        trackTimers[bundleID] = nil
        windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }
        windowsByBundleID[bundleID] = nil
        contentByBundleID[bundleID] = nil
        pidByBundleID[bundleID] = nil
        Log.overlay.info("Overlay dismissed for \(bundleID, privacy: .public)")
    }

    func dismissAll() {
        for bundleID in Array(contentByBundleID.keys) {
            dismissOverlay(for: bundleID)
        }
    }

    // MARK: - Tracking

    /// Match overlay panels to the app's current windows. Called on show and on
    /// every tracking tick, so the cover follows move/resize live.
    private func placeOrUpdate(_ bundleID: String) {
        guard let content = contentByBundleID[bundleID], let pid = pidByBundleID[bundleID] else { return }

        let frames = Self.windowFrames(pid: pid).map { $0.insetBy(dx: -Self.outset, dy: -Self.outset) }
        var windows = windowsByBundleID[bundleID] ?? []

        guard !frames.isEmpty else {
            // No visible window (still launching, or minimised): pull the cover
            // until a window reappears. Tracking keeps running.
            windows.forEach { $0.orderOut(nil) }
            windowsByBundleID[bundleID] = []
            return
        }

        if windows.count != frames.count {
            windows.forEach { $0.orderOut(nil) }
            windows = frames.map { Self.makeOverlayWindow(frame: $0, content: content) }
            windowsByBundleID[bundleID] = windows
            // Order front WITHOUT activating AppLock, so the Touch ID sheet keeps
            // focus and can be completed.
            windows.forEach { $0.orderFrontRegardless() }
        } else {
            for (window, frame) in zip(windows, frames) where window.frame != frame {
                window.setFrame(frame, display: true)
            }
        }
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

    // MARK: - Window geometry

    /// On-screen window frames (Cocoa coordinates) belonging to `pid`. Bounds
    /// are available without Screen Recording permission (only titles/pixels
    /// aren't).
    private static func windowFrames(pid: pid_t) -> [NSRect] {
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
        window.contentView = NSHostingView(rootView: content)
        window.setFrame(frame, display: true)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        return window
    }
}
