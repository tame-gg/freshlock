//
//  OnboardingPresenter.swift
//  FreshLock
//
//  Presents the first-launch setup guide as a standalone window, hosted via
//  `NSHostingController`. Presenting from AppKit (rather than a SwiftUI `Window`
//  scene) is the reliable way to show a window at launch for a menu-bar
//  accessory app that otherwise has no visible windows.
//

import AppKit
import FreshLockCore
import FreshLockEngine
import SwiftUI

/// Tracks and presents onboarding. One instance is owned by the `AppDelegate`.
@MainActor
final class OnboardingPresenter {
    /// Whether the user has completed (or skipped) onboarding before.
    private static let completedKey = "gg.tame.freshlock.hasCompletedOnboarding"

    /// Posted (e.g. from Preferences) to replay the setup guide on demand.
    static let replayNotification = Notification.Name("gg.tame.freshlock.replayOnboarding")

    private let loginItem: LoginItemServiceProtocol
    private let defaults: UserDefaults
    private var windowController: NSWindowController?

    init(loginItem: LoginItemServiceProtocol, defaults: UserDefaults = .standard) {
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
            loginItem: loginItem,
            onFinish: { [weak self] in self?.complete() }
        )
        let preferGlass = AppEnvironment.shared.configurationStore.configuration.settings.preferLiquidGlass
        let root = OnboardingView(viewModel: viewModel)
            .environment(\.preferLiquidGlass, preferGlass)
            .tint(Theme.accent)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to FreshLock"
        // First-run: no close button so the Accessibility gate cannot be skipped by
        // dismissing the window. Replay (already completed) remains closable.
        var styleMask: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]
        if hasCompletedOnboarding {
            styleMask.insert(.closable)
        }
        window.styleMask = styleMask
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 580, height: 600))
        window.minSize = NSSize(width: 540, height: 500)
        window.isReleasedWhenClosed = false
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
        // Open the main window so the first-run user can pick apps to protect.
        WindowManager.shared.showMain()
    }
}
