//
//  OnboardingViewModel.swift
//  FreshLock
//
//  Drives the first-launch setup guide: welcoming the user, priming
//  Accessibility (required for event-driven window covering), offering
//  launch-at-login, and choosing a grace period before switch-away relock.
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
        case gracePeriod
        case done
    }

    /// Drives page slide direction: Continue inserts from trailing, Back from leading.
    enum NavigationDirection {
        case forward
        case backward
    }

    @Published var step: Step = .welcome
    @Published private(set) var navigationDirection: NavigationDirection = .forward
    @Published var launchAtLoginEnabled: Bool
    @Published var gracePeriodSeconds: Int
    @Published var accessibilityTrusted: Bool = AccessibilityPermission.isTrusted
    /// Path of the running `.app` - shown when trust is missing so developers can
    /// match the System Settings row to this process.
    @Published private(set) var runningBundlePath: String = AccessibilityPermission.runningBundlePathDisplay

    private let loginItem: LoginItemServiceProtocol
    private let store: ConfigurationStore
    private let onFinish: () -> Void
    private let onQuit: () -> Void
    private var accessibilityPoll: Timer?
    private var becomeActiveObserver: NSObjectProtocol?

    init(
        loginItem: LoginItemServiceProtocol,
        store: ConfigurationStore,
        onFinish: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.loginItem = loginItem
        self.store = store
        self.onFinish = onFinish
        self.onQuit = onQuit
        launchAtLoginEnabled = loginItem.isEnabled
        gracePeriodSeconds = store.configuration.settings.gracePeriodSeconds
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
        case .welcome, .launchAtLogin, .gracePeriod:
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
            navigationDirection = .forward
            step = nextStep
        }
    }

    func back() {
        if step == .accessibility {
            stopAccessibilityMonitoring()
        }
        if let prev = Step(rawValue: step.rawValue - 1) {
            navigationDirection = .backward
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

    func setGracePeriodSeconds(_ seconds: Int) {
        let clamped = max(0, seconds)
        gracePeriodSeconds = clamped
        store.update { $0.settings.gracePeriodSeconds = clamped }
    }

    func finish() {
        // Defense in depth: never mark onboarding complete without Accessibility.
        refreshAccessibilityStatus()
        guard accessibilityTrusted else {
            navigationDirection = .backward
            step = .accessibility
            startAccessibilityMonitoring()
            return
        }
        stopAccessibilityMonitoring()
        onFinish()
    }

    /// Escape hatch while the first-run window has no close button. Presenter
    /// decides terminate vs dismiss (replay from Preferences).
    func quit() {
        stopAccessibilityMonitoring()
        onQuit()
    }

    // MARK: - Accessibility monitoring

    /// Poll + re-check on foreground while the Accessibility page is visible.
    /// System Settings toggles often only apply to this process after the app
    /// becomes active again.
    func startAccessibilityMonitoring() {
        stopAccessibilityMonitoring()
        refreshAccessibilityStatus()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityStatus()
            }
        }
        // `.common` so the poll keeps firing while the user is in System Settings
        // tracking loops / other modal UI.
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPoll = timer

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
