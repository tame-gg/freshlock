//
//  OnboardingViewModel.swift
//  FreshLock
//
//  Drives the first-launch setup guide: welcoming the user, priming
//  Accessibility (required for event-driven window covering), and offering
//  launch-at-login.
//

import AppKit
import Foundation
import FreshLockCore
import FreshLockEngine

@MainActor
final class OnboardingViewModel: ObservableObject {
    /// The pages of the flow, in order.
    enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case launchAtLogin
        case done
    }

    @Published var step: Step = .welcome
    @Published var launchAtLoginEnabled: Bool
    @Published var accessibilityTrusted: Bool = AccessibilityPermission.isTrusted
    /// Path of the running `.app` — shown when trust is missing so developers can
    /// match the System Settings row to this process.
    @Published private(set) var runningBundlePath: String = AccessibilityPermission.runningBundlePathDisplay

    private let loginItem: LoginItemServiceProtocol
    private let onFinish: () -> Void
    private var accessibilityPoll: Timer?
    private var becomeActiveObserver: NSObjectProtocol?

    init(loginItem: LoginItemServiceProtocol, onFinish: @escaping () -> Void) {
        self.loginItem = loginItem
        self.onFinish = onFinish
        launchAtLoginEnabled = loginItem.isEnabled
    }

    deinit {
        accessibilityPoll?.invalidate()
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
        }
    }

    // MARK: Navigation

    var canGoBack: Bool {
        step != .welcome
    }

    var isLastStep: Bool {
        step == .done
    }

    /// Whether Continue may advance past the current step. Accessibility is a
    /// hard requirement: the user cannot leave that page until **this** process
    /// is trusted (`AXIsProcessTrusted`).
    var canContinue: Bool {
        switch step {
        case .accessibility:
            accessibilityTrusted
        case .welcome, .launchAtLogin:
            true
        case .done:
            false
        }
    }

    func next() {
        refreshAccessibilityStatus()
        guard canContinue else { return }

        if step == .accessibility {
            stopAccessibilityMonitoring()
        }
        if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }

    func back() {
        if step == .accessibility {
            stopAccessibilityMonitoring()
        }
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    // MARK: Actions

    /// Prompt TCC for this binary, then open Accessibility settings if still untrusted.
    func requestAccessibility() {
        accessibilityTrusted = AccessibilityPermission.requestTrust()
        runningBundlePath = AccessibilityPermission.runningBundlePathDisplay
        if !accessibilityTrusted {
            AccessibilityPermission.openSystemSettings()
        }
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
        runningBundlePath = AccessibilityPermission.runningBundlePathDisplay
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            launchAtLoginEnabled = loginItem.isEnabled
        } catch {
            Log.lifecycle.error("Onboarding launch-at-login failed: \(error.localizedDescription)")
            launchAtLoginEnabled = loginItem.isEnabled
        }
    }

    func finish() {
        // Defense in depth: never mark onboarding complete without Accessibility.
        refreshAccessibilityStatus()
        guard accessibilityTrusted else {
            step = .accessibility
            startAccessibilityMonitoring()
            return
        }
        stopAccessibilityMonitoring()
        onFinish()
    }

    // MARK: - Accessibility monitoring

    /// Poll + re-check on foreground while the Accessibility page is visible.
    /// System Settings toggles often only apply to this process after the app
    /// becomes active again.
    func startAccessibilityMonitoring() {
        stopAccessibilityMonitoring()
        refreshAccessibilityStatus()

        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityStatus()
            }
        }
        // Ensure the timer fires while the user is interacting with other UI.
        if let accessibilityPoll {
            RunLoop.main.add(accessibilityPoll, forMode: .common)
        }

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityStatus()
            }
        }
    }

    func stopAccessibilityMonitoring() {
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
            self.becomeActiveObserver = nil
        }
    }
}
