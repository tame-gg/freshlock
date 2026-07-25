//
//  OverlayService.swift
//  AppLock
//
//  Owns the full-screen lock overlay windows. When an app must be locked, the
//  service presents a borderless, top-most window on every screen that hosts
//  the `LockOverlayView`. On success the windows are torn down.
//
//  The overlay window is a floating `NSPanel` at `.screenSaver` level so it
//  sits above ordinary and full-screen app windows. It joins all Spaces and is
//  non-activating where possible so it doesn't steal keyboard focus from the
//  system authentication sheet.
//

import AppKit
import AppLockCore
import SwiftUI

@MainActor
protocol OverlayServiceProtocol: AnyObject {
    /// Whether an overlay is currently shown for the given app.
    func isShowingOverlay(for bundleID: String) -> Bool
    /// Present the lock overlay for an app. `onUnlock` is called when the user
    /// requests authentication.
    func showOverlay(
        for bundleID: String,
        appName: String,
        icon: NSImage,
        method: AuthMethod,
        style: OverlayStyle,
        onUnlock: @escaping () -> Void
    )
    /// Remove the overlay for an app (e.g. after a successful unlock).
    func dismissOverlay(for bundleID: String)
    /// Remove every overlay.
    func dismissAll()
}

@MainActor
final class OverlayService: OverlayServiceProtocol {
    /// One set of windows (one per screen) per locked app.
    private var windowsByBundleID: [String: [NSWindow]] = [:]

    func isShowingOverlay(for bundleID: String) -> Bool {
        !(windowsByBundleID[bundleID]?.isEmpty ?? true)
    }

    func showOverlay(
        for bundleID: String,
        appName: String,
        icon: NSImage,
        method: AuthMethod,
        style: OverlayStyle,
        onUnlock: @escaping () -> Void
    ) {
        guard !isShowingOverlay(for: bundleID) else { return }

        let root = LockOverlayView(
            appName: appName,
            icon: Image(nsImage: icon),
            method: method,
            style: style,
            onUnlock: onUnlock
        )

        var windows: [NSWindow] = []
        for screen in NSScreen.screens {
            let window = Self.makeOverlayWindow(frame: screen.frame)
            window.contentView = NSHostingView(rootView: root)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windowsByBundleID[bundleID] = windows
        Log.overlay.info("Presented overlay for \(bundleID, privacy: .public)")
    }

    func dismissOverlay(for bundleID: String) {
        windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }
        windowsByBundleID[bundleID] = nil
        Log.overlay.info("Dismissed overlay for \(bundleID, privacy: .public)")
    }

    func dismissAll() {
        for bundleID in windowsByBundleID.keys {
            windowsByBundleID[bundleID]?.forEach { $0.orderOut(nil) }
        }
        windowsByBundleID.removeAll()
    }

    private static func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
