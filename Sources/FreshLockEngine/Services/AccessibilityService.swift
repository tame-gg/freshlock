//
//  AccessibilityService.swift
//  FreshLockEngine
//
//  Primary control surface for securing protected apps. Uses the macOS
//  Accessibility (AX) API to:
//
//  • Detect window creation / move / resize as soon as the OS publishes it
//  • Read on-screen window frames for overlay placement
//  • Report whether the host process is trusted for Accessibility
//
//  Interaction blocking is still done by the non-activating overlay — AX has
//  no public "freeze another app" action. What AX *does* give us is earlier,
//  event-driven awareness of the protected UI so we can cover it without
//  hiding, minimizing, or reactivating the target (all of which interrupt
//  LocalAuthentication).
//

import AppKit
import ApplicationServices
import Foundation
import FreshLockCore

/// Host / system bundle IDs that participate in the lock flow but are not
/// themselves protected targets. Kept in one place so overlay covering and
/// switch-away logic stay aligned.
enum FreshLockIdentity {
    static let mainBundleID = "gg.tame.freshlock"
    static let helperBundleID = "gg.tame.freshlock.helper"
    static let localAuthUIAgent = "com.apple.LocalAuthentication.UIAgent"

    /// Bundle IDs whose activation is a transient side effect of locking /
    /// authenticating, not a real user app switch.
    static let transientFrontmostBundleIDs: Set<String> = [
        mainBundleID,
        helperBundleID,
        localAuthUIAgent
    ]
}

/// Public Accessibility permission helpers for the GUI (onboarding / Preferences).
///
/// Trust is always evaluated for the **currently running process** via
/// `AXIsProcessTrusted`. System Settings can show a different FreshLock.app
/// (another path or code signature) as enabled while this process remains
/// untrusted - common when switching between Xcode, `dist/`, and `/Applications`.
@MainActor
public enum AccessibilityPermission {
    /// Whether **this** process is currently trusted for Accessibility.
    public static var isTrusted: Bool {
        // Prefer the options API with prompt disabled so we never accidentally
        // surface a sheet from a status poll / foreground refresh.
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Absolute path of the running app bundle (TCC identity tip for developers).
    public static var runningBundlePath: String {
        Bundle.main.bundlePath
    }

    /// Home-abbreviated bundle path for UI copy (`~/…`).
    public static var runningBundlePathDisplay: String {
        (runningBundlePath as NSString).abbreviatingWithTildeInPath
    }

    /// Prompt TCC for **this** binary (system sheet / Settings registration), then
    /// return the post-prompt trust state. Does not open System Settings itself.
    @discardableResult
    public static func requestTrust() -> Bool {
        // Use the documented option key string rather than the HIServices global
        // (which is not concurrency-safe under Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    public static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

@MainActor
protocol AccessibilityServiceProtocol: AnyObject {
    var isTrusted: Bool { get }
    /// Begin observing window lifecycle for `pid`. `onChange` is always
    /// invoked on the main actor when a relevant AX notification fires.
    func startWatching(pid: pid_t, onChange: @escaping @MainActor () -> Void)
    func stopWatching(pid: pid_t)
    func stopWatchingAll()
    /// On-screen window frames for `pid` via AX (empty if untrusted / no windows).
    func windowFrames(pid: pid_t) -> [NSRect]
}

/// Refcon payload for the C AXObserver callback. Retained for the life of the
/// observation; the callback only takes an unretained reference.
///
/// `@unchecked Sendable` because the C callback hops to the main queue before
/// touching `onChange`, and the instance is only mutated on the main actor.
private final class AXObservation: @unchecked Sendable {
    let pid: pid_t
    var observer: AXObserver?
    var onChange: @MainActor () -> Void

    init(pid: pid_t, onChange: @escaping @MainActor () -> Void) {
        self.pid = pid
        self.onChange = onChange
    }
}

@MainActor
final class AccessibilityService: AccessibilityServiceProtocol {
    private var observations: [pid_t: AXObservation] = [:]

    var isTrusted: Bool {
        AccessibilityPermission.isTrusted
    }

    func startWatching(pid: pid_t, onChange: @escaping @MainActor () -> Void) {
        stopWatching(pid: pid)
        guard isTrusted, pid > 0 else { return }

        let observation = AXObservation(pid: pid, onChange: onChange)

        var observer: AXObserver?
        let status = AXObserverCreate(pid, axObserverCallback, &observer)
        guard status == .success, let observer else {
            Log.accessibility.error("AXObserverCreate failed for pid \(pid): \(status.rawValue)")
            return
        }

        // Retain via `observations`; the C callback only takes an unretained ref.
        observations[pid] = observation
        let refcon = Unmanaged.passUnretained(observation).toOpaque()

        let app = AXUIElementCreateApplication(pid)
        let notifications = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXApplicationShownNotification,
            kAXApplicationHiddenNotification
        ] as [CFString]

        for name in notifications {
            let addStatus = AXObserverAddNotification(observer, app, name, refcon)
            if addStatus != .success {
                Log.accessibility.debug(
                    "AX add \(String(describing: name), privacy: .public) for pid \(pid): \(addStatus.rawValue)"
                )
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observation.observer = observer
        Log.accessibility.info("AX watching pid \(pid)")
    }

    func stopWatching(pid: pid_t) {
        guard let observation = observations.removeValue(forKey: pid) else { return }
        if let observer = observation.observer {
            let app = AXUIElementCreateApplication(pid)
            let notifications = [
                kAXWindowCreatedNotification,
                kAXUIElementDestroyedNotification,
                kAXFocusedWindowChangedNotification,
                kAXMainWindowChangedNotification,
                kAXWindowMovedNotification,
                kAXWindowResizedNotification,
                kAXApplicationShownNotification,
                kAXApplicationHiddenNotification
            ] as [CFString]
            for name in notifications {
                AXObserverRemoveNotification(observer, app, name)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observation.observer = nil
        Log.accessibility.debug("AX stopped watching pid \(pid)")
    }

    func stopWatchingAll() {
        for pid in Array(observations.keys) {
            stopWatching(pid: pid)
        }
    }

    func windowFrames(pid: pid_t) -> [NSRect] {
        guard isTrusted, pid > 0 else { return [] }
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
            let windows = windowsRef as? [AXUIElement]
        else {
            return []
        }

        var frames: [NSRect] = []
        for window in windows {
            guard let frame = Self.frame(for: window) else { continue }
            // Ignore tiny utility / chrome fragments; match OverlayService filter.
            guard frame.width >= 80, frame.height >= 80 else { continue }
            // Skip minimized / hidden windows when AX reports them.
            if Self.isMinimized(window) {
                continue
            }
            frames.append(frame)
        }
        return frames
    }

    // MARK: - AX helpers

    private static func frame(for element: AXUIElement) -> NSRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef
        ) == .success,
            AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeRef
            ) == .success,
            let positionValue = positionRef,
            let sizeValue = sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAX = unsafeDowncast(positionValue as AnyObject, to: AXValue.self)
        let sizeAX = unsafeDowncast(sizeValue as AnyObject, to: AXValue.self)
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size)
        else {
            return nil
        }
        // AX reports global coordinates with the origin at the top-left of the
        // main display; Cocoa windows use bottom-left. Convert before returning.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            return NSRect(origin: position, size: size)
        }
        let cocoaY = primaryHeight - position.y - size.height
        return NSRect(x: position.x, y: cocoaY, width: size.width, height: size.height)
    }

    private static func isMinimized(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXMinimizedAttribute as CFString, &ref
        ) == .success,
            let value = ref as? Bool else { return false }
        return value
    }
}

/// C callback bridge. Hop to the main actor before invoking the observation.
private func axObserverCallback(
    _: AXObserver,
    _: AXUIElement,
    _: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let observation = Unmanaged<AXObservation>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            observation.onChange()
        }
    }
}
