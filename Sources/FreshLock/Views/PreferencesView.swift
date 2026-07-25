//
//  PreferencesView.swift
//  FreshLock
//
//  The Preferences window, redesigned to match the app's koels.net dark theme:
//  a single scrollable page of grouped, card-style sections rather than the
//  cramped default tabbed Form. All controls bind to `SettingsViewModel`.
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

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel("Preferences")
                        Text("Settings").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                    }
                    generalSection
                    lockingSection
                    shortcutsSection
                    backupSection
                    advancedSection
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 500, height: 640)
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Launch at login") {
                toggle(viewModel.launchAtLogin)
            }
            if let error = viewModel.loginItemError {
                note(error, error: true)
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Show icon in menu bar",
                        subtitle: showMenuBarIcon ? nil : "Reopen FreshLock from Finder or Spotlight to bring back its window.") {
                toggle($showMenuBarIcon)
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Notify when a protected app launches") {
                toggle(viewModel.binding(\.notifyOnProtectedLaunch))
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Overlay style") {
                Picker("", selection: viewModel.binding(\.overlayStyle)) {
                    ForEach(OverlayStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize().tint(Theme.textSecondary)
            }
        }
    }

    private var lockingSection: some View {
        SettingsSection("Locking") {
            SettingsRow("Default relock",
                        subtitle: "\u{201C}When switching away\u{201D} matches iOS — re-asks each time you return.") {
                Picker("", selection: defaultRelockKind) {
                    ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize().tint(Theme.textSecondary)
            }
            if defaultRelockKind.wrappedValue.needsMinutes {
                Divider().overlay(Theme.stroke)
                SettingsRow("Minutes") {
                    Stepper("\(defaultRelockMinutes.wrappedValue)", value: defaultRelockMinutes, in: 1...240)
                        .fixedSize()
                }
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Require authentication on every launch",
                        subtitle: "Prompt on every activation, even if this process was already unlocked. Quitting always clears unlock regardless of this setting.") {
                toggle(viewModel.binding(\.requireEveryLaunch))
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Grace period") {
                Stepper("\(viewModel.settings.gracePeriodSeconds)s",
                        value: viewModel.binding(\.gracePeriodSeconds), in: 0...60).fixedSize()
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection("Global Shortcuts") {
            SettingsRow("Lock All") {
                ShortcutRecorderView(shortcut: viewModel.binding(\.lockAllShortcut)).frame(width: 150, height: 26)
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Unlock All") {
                ShortcutRecorderView(shortcut: viewModel.binding(\.unlockAllShortcut)).frame(width: 150, height: 26)
            }
            note("Each shortcut needs at least one of ⌘/⌥/⌃. Press ⌫ while recording to clear.")
        }
    }

    private var backupSection: some View {
        SettingsSection("Backup") {
            SettingsRow("Export configuration") {
                accentButton("Export…", action: exportConfiguration)
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Import configuration") {
                accentButton("Import…", action: importConfiguration)
            }
            if let backupStatus {
                note(backupStatus, error: backupIsError)
            }
            note("A single JSON file with your protected apps and preferences. It never contains passwords.")
        }
    }

    private var advancedSection: some View {
        SettingsSection("Advanced") {
            SettingsRow("Accessibility",
                        subtitle: AccessibilityPermission.isTrusted
                        ? "Granted — window covering uses Accessibility."
                        : "Required for reliable locking. Open System Settings to enable FreshLock.") {
                if AccessibilityPermission.isTrusted {
                    Text("Granted")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    accentButton("Open Settings…") {
                        AccessibilityPermission.requestTrust()
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }
            Divider().overlay(Theme.stroke)
            SettingsRow("Developer mode") { toggle(viewModel.binding(\.developerMode)) }
            Divider().overlay(Theme.stroke)
            SettingsRow("Setup guide") {
                accentButton("Replay…") {
                    NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
                }
            }
        }
    }

    // MARK: Reusable controls

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).tint(Theme.green)
    }

    private func accentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, error: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(error ? Color.red : Theme.textMuted)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bindings

    private var relockPolicy: Binding<RelockPolicy> { viewModel.binding(\.defaultRelockPolicy) }

    private var defaultRelockKind: Binding<PolicyKind> {
        .init(
            get: { PolicyKind(from: relockPolicy.wrappedValue) },
            set: { relockPolicy.wrappedValue = $0.makePolicy(minutes: defaultRelockMinutes.wrappedValue) ?? .everyLaunch }
        )
    }

    private var defaultRelockMinutes: Binding<Int> {
        .init(
            get: { relockPolicy.wrappedValue.minutes ?? 15 },
            set: { relockPolicy.wrappedValue = PolicyKind(from: relockPolicy.wrappedValue).makePolicy(minutes: $0) ?? .everyLaunch }
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

// MARK: - Building blocks

/// A titled card section in the koels dark style.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(title)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
        }
    }
}

/// A single labelled row with a trailing control.
private struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 11)
    }
}
