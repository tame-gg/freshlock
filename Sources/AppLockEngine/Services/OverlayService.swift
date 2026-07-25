//
//  OverlayService.swift
//  AppLockEngine
//
//  Owns the lock overlay windows. Rather than blanking the whole display, the
//  overlay covers only the *protected app's own windows*: we look up the app's
//  on-screen window frames and place one borderless, top-most panel over each.
//  This feels like iOS app-lock (the rest of the desktop stays usable) instead
//  of a full-screen takeover.
//
//  Timing: when an app is *launching*, its window often doesn't exist yet at the
//  instant we must lock. We therefore cover the active screen immediately (so
//  there's never an interactive gap) and then briefly poll for the app's real
//  window, refitting the overlay to it the moment it appears.
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

@MainActor
final class OverlayService: OverlayServiceProtocol {
    private var windowsByBundleID: [String: [NSWindow]] = [:]
    /// The rendered content per overlay, kept so we can rebuild panels when we
    /// refit to the app's real window (stored on `self` to avoid capturing
    /// non-`Sendable` views in the refit timer closure).
    private var contentByBundleID: [String: LockOverlayView] = [:]
    private var refitTimers: [String: Timer] = [:]

    func isShowingOverlay(for bundleID: String) -> Bool {
        !(windowsByBundleID[bundleID]?.isEmpty ?? true)
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
        guard !isShowingOverlay(for: bundleID) else { return }

        let content = LockOverlayView(
            appName: appName,
            icon: Image(nsImage: icon),
            method: method,
            style: style,
            onUnlock: onUnlock,
            onCancel: onCancel
        )
        contentByBundleID[bundleID] = content

        let frames = Self.windowFrames(pid: pid)
        presentPanels(for: bundleID, frames: frames.isEmpty ? Self.fallbackFrames() : frames)

        // If we couldn't fit the real window yet, keep trying briefly.
        if frames.isEmpty {
            startRefit(for: bundleID, pid: pid)
        }
    }

    func dismissOverlay(for bundleID: String) {
        refitTimers[bundleID]?.invalidate()
        refitTimers[bundleID] = nil
        contentByBundleID[bundleID] = nil
        windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }
        windowsByBundleID[bundleID] = nil
        Log.overlay.info("Dismissed overlay for \(bundleID, privacy: .public)")
    }

    func dismissAll() {
        for bundleID in Array(windowsByBundleID.keys) {
            dismissOverlay(for: bundleID)
        }
    }

    // MARK: - Panel management

    private func presentPanels(for bundleID: String, frames: [NSRect]) {
        guard let content = contentByBundleID[bundleID] else { return }
        // Replace any existing panels (used both for first show and refit).
        windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }

        var windows: [NSWindow] = []
        for frame in frames {
            let window = Self.makeOverlayWindow(frame: frame)
            window.contentView = NSHostingView(rootView: content)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windowsByBundleID[bundleID] = windows
        Log.overlay.info("Presented \(windows.count) overlay(s) for \(bundleID, privacy: .public)")
    }

    /// Poll (briefly, on the main run loop) for the app's real window and refit
    /// the overlay to it once it appears.
    private func startRefit(for bundleID: String, pid: pid_t) {
        refitTimers[bundleID]?.invalidate()
        var attempts = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                attempts += 1
                guard self.isShowingOverlay(for: bundleID) else { self.stopRefit(bundleID); return }
                let frames = Self.windowFrames(pid: pid)
                if !frames.isEmpty {
                    self.presentPanels(for: bundleID, frames: frames)
                    self.stopRefit(bundleID)
                } else if attempts >= 20 { // ~3s
                    self.stopRefit(bundleID)
                }
            }
        }
        refitTimers[bundleID] = timer
    }

    private func stopRefit(_ bundleID: String) {
        refitTimers[bundleID]?.invalidate()
        refitTimers[bundleID] = nil
    }

    // MARK: - Window geometry

    /// On-screen window frames (in Cocoa coordinates) belonging to `pid`.
    ///
    /// `CGWindowListCopyWindowInfo` reports normal app windows at layer 0 with
    /// bounds in a top-left origin global space; we convert to AppKit's
    /// bottom-left origin using the primary screen's height. Bounds are
    /// available without Screen Recording permission (only titles/pixels aren't).
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

    /// Full frame of the primary screen, used only until the app's window
    /// appears.
    private static func fallbackFrames() -> [NSRect] {
        if let screen = NSScreen.main { return [screen.frame] }
        return NSScreen.screens.map(\.frame)
    }

    private static func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: true)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        return window
    }
}
