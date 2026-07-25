//
//  PreferencesView.swift
//  AppLock
//
//  The Preferences window, laid out as a standard macOS `Form` with grouped
//  sections. Every control is bound directly to `SettingsViewModel.settings`,
//  which persists on change.
//

import AppKit
import AppLockCore
import AppLockEngine
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage(MenuBarPreference.key) private var showMenuBarIcon = true
    @State private var backupStatus: String?
    @State private var backupIsError = false

    init(store: ConfigurationStore, loginItem: LoginItemServiceProtocol) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(store: store, loginItem: loginItem))
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            lockingTab.tabItem { Label("Locking", systemImage: "lock") }
            shortcutsTab.tabItem { Label("Shortcuts", systemImage: "command") }
            backupTab.tabItem { Label("Backup", systemImage: "arrow.up.arrow.down.circle") }
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
            Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
            if !showMenuBarIcon {
                Text("Reopen AppLock from Finder or Spotlight to bring back its window.")
                    .font(.caption).foregroundStyle(.secondary)
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
            Picker("Default relock", selection: defaultRelockKind) {
                ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if defaultRelockKind.wrappedValue.needsMinutes {
                Stepper("After \(defaultRelockMinutes.wrappedValue) min", value: defaultRelockMinutes, in: 1...240)
            }
            Text("Applies to apps set to \u{201C}Default\u{201D}. \u{201C}Once per launch\u{201D} prompts only when you open an app, not each time you switch back.")
                .font(.caption).foregroundStyle(.secondary)

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

    /// The global default relock policy, mapped to the flat `PolicyKind` picker
    /// (there is no "Default" option here — this *is* the default).
    private var defaultRelockKind: Binding<PolicyKind> {
        .init(
            get: { PolicyKind(from: viewModel.settings.defaultRelockPolicy) },
            set: { viewModel.settings.defaultRelockPolicy =
                $0.makePolicy(minutes: defaultRelockMinutes.wrappedValue) ?? .everyLaunch }
        )
    }

    private var defaultRelockMinutes: Binding<Int> {
        .init(
            get: { viewModel.settings.defaultRelockPolicy.minutes ?? 15 },
            set: { viewModel.settings.defaultRelockPolicy =
                PolicyKind(from: viewModel.settings.defaultRelockPolicy).makePolicy(minutes: $0) ?? .everyLaunch }
        )
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                LabeledContent("Lock All") {
                    ShortcutRecorderView(shortcut: $viewModel.settings.lockAllShortcut)
                        .frame(width: 150, height: 24)
                }
                LabeledContent("Unlock All") {
                    ShortcutRecorderView(shortcut: $viewModel.settings.unlockAllShortcut)
                        .frame(width: 150, height: 24)
                }
            } footer: {
                Text("System-wide shortcuts. Lock All immediately relocks every app; Unlock All authenticates once and unlocks all protected apps until sleep. Each shortcut needs at least one of ⌘/⌥/⌃. Press ⌫ while recording to clear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Backup

    private var backupTab: some View {
        Form {
            Section {
                LabeledContent("Export configuration") {
                    Button("Export…", action: exportConfiguration)
                }
                LabeledContent("Import configuration") {
                    Button("Import…", action: importConfiguration)
                }
            } footer: {
                Text("Configuration is a single JSON document containing your protected apps and preferences — safe to back up or move between Macs. It never contains passwords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let backupStatus {
                Text(backupStatus)
                    .font(.caption)
                    .foregroundStyle(backupIsError ? .red : .green)
            }
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AppLock-configuration.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.exportConfiguration(to: url)
            setStatus("Exported to \(url.lastPathComponent).", isError: false)
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.importConfiguration(from: url)
            setStatus("Imported from \(url.lastPathComponent).", isError: false)
        } catch {
            setStatus("Import failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        backupStatus = message
        backupIsError = isError
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Form {
            Toggle("Developer Mode", isOn: $viewModel.settings.developerMode)
            LabeledContent("Accessibility", value: AccessibilityStatusText.current)
            LabeledContent("Setup Guide") {
                Button("Replay…") {
                    NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
                }
            }
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
