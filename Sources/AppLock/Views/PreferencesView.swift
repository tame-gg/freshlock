//
//  PreferencesView.swift
//  AppLock
//
//  The Preferences window, laid out as a standard macOS `Form` with grouped
//  sections. Every control is bound directly to `SettingsViewModel.settings`,
//  which persists on change.
//

import AppLockCore
import AppLockEngine
import ApplicationServices
import SwiftUI

struct PreferencesView: View {
    @StateObject private var viewModel: SettingsViewModel

    init(
        settingsService: SettingsServiceProtocol,
        loginItem: LoginItemServiceProtocol,
        initialConfiguration: Configuration
    ) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            settingsService: settingsService,
            loginItem: loginItem,
            initialConfiguration: initialConfiguration
        ))
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            lockingTab.tabItem { Label("Locking", systemImage: "lock") }
            advancedTab.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 460)
        .padding()
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Toggle("Launch at Login", isOn: $viewModel.settings.launchAtLogin)
            if let error = viewModel.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Notify when a protected app launches", isOn: $viewModel.settings.notifyOnProtectedLaunch)
            Picker("Overlay Style", selection: $viewModel.settings.overlayStyle) {
                ForEach(OverlayStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
        }
    }

    // MARK: Locking

    private var lockingTab: some View {
        Form {
            Toggle("Require authentication on every launch", isOn: $viewModel.settings.requireEveryLaunch)
            Stepper(
                "Grace period: \(viewModel.settings.gracePeriodSeconds)s",
                value: $viewModel.settings.gracePeriodSeconds,
                in: 0...60
            )
            Stepper(
                "Default inactivity timeout: \(viewModel.settings.defaultInactivityMinutes) min",
                value: $viewModel.settings.defaultInactivityMinutes,
                in: 1...120
            )
        }
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Form {
            Toggle("Developer Mode", isOn: $viewModel.settings.developerMode)
            LabeledContent("Accessibility", value: AccessibilityStatusText.current)
            Text("Verbose logging is written to the unified log under subsystem gg.tame.applock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small helper that reports the current Accessibility trust state as text.
private enum AccessibilityStatusText {
    static var current: String {
        AXIsProcessTrusted() ? "Granted" : "Not granted"
    }
}
