//
//  OnboardingPresenter.swift
//  AppLock
//
//  Presents the first-launch setup guide as a standalone window, hosted via
//  `NSHostingController`. Presenting from AppKit (rather than a SwiftUI `Window`
//  scene) is the reliable way to show a window at launch for a menu-bar
//  accessory app that otherwise has no visible windows.
//

import AppKit
import AppLockCore
import AppLockEngine
import SwiftUI

/// Tracks and presents onboarding. One instance is owned by the `AppDelegate`.
@MainActor
final class OnboardingPresenter {
    /// Whether the user has completed (or skipped) onboarding before.
    private static let completedKey = "gg.tame.applock.hasCompletedOnboarding"

    /// Posted (e.g. from Preferences) to replay the setup guide on demand.
    static let replayNotification = Notification.Name("gg.tame.applock.replayOnboarding")

    private let accessibility: AccessibilityServiceProtocol
    private let loginItem: LoginItemServiceProtocol
    private let defaults: UserDefaults
    private var windowController: NSWindowController?

    init(
        accessibility: AccessibilityServiceProtocol,
        loginItem: LoginItemServiceProtocol,
        defaults: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.loginItem = loginItem
        self.defaults = defaults
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Self.completedKey)
    }

    /// Show onboarding if it hasn't been completed yet.
    func presentIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        present()
    }

    /// Force-show onboarding (used by the "Replay Setup Guide" action).
    func present() {
        guard windowController == nil else {
            windowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = OnboardingViewModel(
            accessibility: accessibility,
            loginItem: loginItem,
            onFinish: { [weak self] in self?.complete() }
        )
        let hosting = NSHostingController(rootView: OnboardingView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to AppLock"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete() {
        defaults.set(true, forKey: Self.completedKey)
        windowController?.close()
        windowController = nil
        Log.lifecycle.info("Onboarding completed")
    }
}
