//
//  AccessibilityService.swift
//  AppLock
//
//  Thin wrapper around the Accessibility (AX) trust APIs. AppLock uses
//  Accessibility permission to raise/position overlay windows over other apps
//  and, where possible, to hide protected windows until authenticated.
//
//  macOS honesty note: Accessibility permission lets us observe and nudge
//  window state, but macOS does not allow one app to forcibly freeze another
//  app's event loop. Our strongest guarantee is a top-most overlay that
//  intercepts interaction; see ARCHITECTURE.md for the full threat model.
//

import ApplicationServices
import Foundation
import AppLockCore

@MainActor
public protocol AccessibilityServiceProtocol: AnyObject {
    /// Whether the process is currently trusted for Accessibility.
    var isTrusted: Bool { get }
    /// Prompt the user to grant Accessibility (opens System Settings pane).
    func requestAccess()
}

@MainActor
public final class AccessibilityService: AccessibilityServiceProtocol {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func requestAccess() {
        // Passing the prompt option shows the system dialog if not yet trusted.
        // Use the literal key to avoid referencing the non-Sendable global
        // `kAXTrustedCheckOptionPrompt`; the string value is stable API.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.accessibility.info("Requested Accessibility access; trusted=\(trusted)")
    }
}
