//
//  OnboardingViewModel.swift
//  FreshLock
//
//  Drives the first-launch setup guide: welcoming the user, priming
//  Accessibility (required for event-driven window covering), and offering
//  launch-at-login.
//

import FreshLockCore
import FreshLockEngine
import Foundation

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

    private let loginItem: LoginItemServiceProtocol
    private let onFinish: () -> Void
    private var accessibilityPoll: Timer?

    init(loginItem: LoginItemServiceProtocol, onFinish: @escaping () -> Void) {
        self.loginItem = loginItem
        self.onFinish = onFinish
        self.launchAtLoginEnabled = loginItem.isEnabled
    }

    // MARK: Navigation

    var canGoBack: Bool { step != .welcome }
    var isLastStep: Bool { step == .done }

    func next() {
        if step == .accessibility {
            stopAccessibilityPoll()
        }
        if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
            if nextStep == .accessibility {
                startAccessibilityPoll()
            }
        }
    }

    func back() {
        if step == .accessibility {
            stopAccessibilityPoll()
        }
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
            if prev == .accessibility {
                startAccessibilityPoll()
            }
        }
    }

    // MARK: Actions

    func requestAccessibility() {
        accessibilityTrusted = AccessibilityPermission.requestTrust()
        if !accessibilityTrusted {
            AccessibilityPermission.openSystemSettings()
        }
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
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
        stopAccessibilityPoll()
        onFinish()
    }

    // MARK: - Accessibility polling

    /// Poll while the Accessibility page is visible so enabling the toggle in
    /// System Settings updates the UI without requiring a restart.
    private func startAccessibilityPoll() {
        stopAccessibilityPoll()
        refreshAccessibilityStatus()
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityStatus()
            }
        }
    }

    private func stopAccessibilityPoll() {
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
    }
}
