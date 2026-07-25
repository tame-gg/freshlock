//
//  OnboardingViewModel.swift
//  AppLock
//
//  Drives the first-launch setup guide: welcoming the user, honestly framing
//  what AppLock can and can't do, and offering launch-at-login. AppLock does not
//  require Accessibility permission (it uses only public APIs that don't need
//  it), so there is no permission step here.
//

import AppLockCore
import AppLockEngine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    /// The pages of the flow, in order.
    enum Step: Int, CaseIterable {
        case welcome
        case launchAtLogin
        case done
    }

    @Published var step: Step = .welcome
    @Published var launchAtLoginEnabled: Bool

    private let loginItem: LoginItemServiceProtocol
    private let onFinish: () -> Void

    init(loginItem: LoginItemServiceProtocol, onFinish: @escaping () -> Void) {
        self.loginItem = loginItem
        self.onFinish = onFinish
        self.launchAtLoginEnabled = loginItem.isEnabled
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
        onFinish()
    }
}
