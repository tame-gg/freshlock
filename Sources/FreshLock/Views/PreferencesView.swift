//
//  PreferencesView.swift
//  FreshLock
//
//  Preferences as a native grouped Form. Includes the Liquid Glass preference
//  (applied to FreshLock chrome when macOS 26+ APIs are available).
//

import AppKit
import FreshLockCore
import FreshLockEngine
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

    private var preferGlass: Bool {
        viewModel.settings.preferLiquidGlass
    }

    var body: some View {
        Form {
            generalSection
            appearanceSection
            lockingSection
            shortcutsSection
            backupSection
            advancedSection
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .environment(\.preferLiquidGlass, preferGlass)
        .frame(width: 500, height: 640)
    }

    // MARK: Sections

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: viewModel.launchAtLogin)
            if let error = viewModel.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
            if !showMenuBarIcon {
                Text("Reopen FreshLock from Finder or Spotlight to bring back its window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Notify when a protected app launches", isOn: viewModel.binding(\.notifyOnProtectedLaunch))
            Picker("Overlay style", selection: viewModel.binding(\.overlayStyle)) {
                ForEach(OverlayStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            // Remains enabled on older OS so the preference persists; glass is a
            // no-op until macOS 26+ (see LiquidGlass.swift).
            Toggle("Use Liquid Glass", isOn: viewModel.binding(\.preferLiquidGlass))
            Text(LiquidGlassSupport.availabilityNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Appearance")
        } footer: {
            Text(
                """
                Controls FreshLock surfaces only. System chrome still follows macOS; \
                on macOS 27 use System Settings → Appearance to adjust glass tint.
                """
            )
        }
    }

    private var lockingSection: some View {
        Section("Locking") {
            Picker("Default relock", selection: defaultRelockKind) {
                ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text("“When switching away” matches iOS — re-asks each time you return.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if defaultRelockKind.wrappedValue.needsMinutes {
                Stepper("Minutes: \(defaultRelockMinutes.wrappedValue)", value: defaultRelockMinutes, in: 1...240)
            }
            Toggle("Require authentication on every launch", isOn: viewModel.binding(\.requireEveryLaunch))
            Text(
                """
                Prompt on every activation, even if this process was already unlocked. \
                Quitting always clears unlock regardless of this setting.
                """
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                "Grace period: \(viewModel.settings.gracePeriodSeconds)s",
                value: viewModel.binding(\.gracePeriodSeconds),
                in: 0...60
            )
        }
    }

    private var shortcutsSection: some View {
        Section {
            LabeledContent("Lock All") {
                ShortcutRecorderView(shortcut: viewModel.binding(\.lockAllShortcut))
                    .frame(width: 150, height: 26)
            }
            LabeledContent("Unlock All") {
                ShortcutRecorderView(shortcut: viewModel.binding(\.unlockAllShortcut))
                    .frame(width: 150, height: 26)
            }
        } header: {
            Text("Global Shortcuts")
        } footer: {
            Text("Each shortcut needs at least one of ⌘/⌥/⌃. Press ⌫ while recording to clear.")
        }
    }

    private var backupSection: some View {
        Section {
            Button("Export configuration…", action: exportConfiguration)
            Button("Import configuration…", action: importConfiguration)
            if let backupStatus {
                Text(backupStatus)
                    .font(.caption)
                    .foregroundStyle(backupIsError ? .red : .secondary)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A single JSON file with your protected apps and preferences. It never contains passwords.")
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            LabeledContent("Accessibility") {
                if AccessibilityPermission.isTrusted {
                    Text("Granted")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Open Settings…") {
                        AccessibilityPermission.requestTrust()
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }
            if !AccessibilityPermission.isTrusted {
                Text("Required for reliable locking. Open System Settings to enable FreshLock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Developer mode", isOn: viewModel.binding(\.developerMode))
            Button("Replay setup guide…") {
                NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
            }
        }
    }

    // MARK: Bindings

    private var relockPolicy: Binding<RelockPolicy> { viewModel.binding(\.defaultRelockPolicy) }

    private var defaultRelockKind: Binding<PolicyKind> {
        .init(
            get: { PolicyKind(from: relockPolicy.wrappedValue) },
            set: { kind in
                let minutes = defaultRelockMinutes.wrappedValue
                relockPolicy.wrappedValue = kind.makePolicy(minutes: minutes) ?? .everyLaunch
            }
        )
    }

    private var defaultRelockMinutes: Binding<Int> {
        .init(
            get: { relockPolicy.wrappedValue.minutes ?? 15 },
            set: { minutes in
                let kind = PolicyKind(from: relockPolicy.wrappedValue)
                relockPolicy.wrappedValue = kind.makePolicy(minutes: minutes) ?? .everyLaunch
            }
        )
    }

    // MARK: Backup actions

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FreshLock-configuration.json"
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
}
