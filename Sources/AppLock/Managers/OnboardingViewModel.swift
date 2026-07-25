//
//  OnboardingViewModel.swift
//  AppLock
//
//  Drives the first-launch setup guide: welcoming the user, honestly framing
//  what AppLock can and can't do, priming the Accessibility permission, and
//  offering launch-at-login. It owns the small amount of live state the flow
//  needs (chiefly the Accessibility trust status, which can change while the
//  window is open as the user grants it in System Settings).
//

import AppLockCore
import AppLockEngine
import Combine
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
    @Published private(set) var isAccessibilityTrusted: Bool
    @Published var launchAtLoginEnabled: Bool

    private let accessibility: AccessibilityServiceProtocol
    private let loginItem: LoginItemServiceProtocol
    private let onFinish: () -> Void
    /// Short-lived poll: Accessibility trust doesn't post a notification, so we
    /// re-check on a modest interval *only while the guide is open*.
    private var pollTimer: Timer?

    init(
        accessibility: AccessibilityServiceProtocol,
        loginItem: LoginItemServiceProtocol,
        onFinish: @escaping () -> Void
    ) {
        self.accessibility = accessibility
        self.loginItem = loginItem
        self.onFinish = onFinish
        self.isAccessibilityTrusted = accessibility.isTrusted
        self.launchAtLoginEnabled = loginItem.isEnabled
        startPolling()
    }

    private func startPolling() {
        // Fires on the main run loop. Self-invalidates once the view model is
        // gone, so a window closed without finishing never leaks a live timer.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.refreshAccessibility() }
        }
    }

    private func refreshAccessibility() {
        let trusted = accessibility.isTrusted
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
    }

    // MARK: Navigation

    var canGoBack: Bool { step != .welcome }
    var isLastStep: Bool { step == .done }

    func next() {
        if let nextStep = Step(rawValue: step.rawValue + 1) {
            step = nextStep
        }
    }

    func back() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    // MARK: Actions

    /// Trigger the system Accessibility prompt / open the settings pane.
    func grantAccessibility() {
        accessibility.requestAccess()
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
        pollTimer?.invalidate()
        pollTimer = nil
        onFinish()
    }
}
