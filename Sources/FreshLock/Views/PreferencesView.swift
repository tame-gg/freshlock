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
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var systemExtensionRegistrar = SystemExtensionRegistrar()

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
            Toggle("Show icon in menu bar", isOn: viewModel.showMenuBarIcon)
            if !viewModel.showMenuBarIcon.wrappedValue {
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
                on macOS 27 use System Settings > Appearance to adjust glass tint.
                """
            )
        }
    }

    private var lockingSection: some View {
        Section("Locking") {
            Picker("Default relock", selection: defaultRelockKind) {
                ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text("\"When switching away\" matches iOS - re-asks each time you return.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if defaultRelockKind.wrappedValue.needsMinutes {
                Stepper("Minutes: \(defaultRelockMinutes.wrappedValue)", value: defaultRelockMinutes, in: 1 ... 240)
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
                in: 0 ... 60
            )
            Text(
                """
                After a successful unlock, wait this long before "when switching away" \
                relocks. Softens focus flicker without weakening lock-on-quit.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if defaultRelockKind.wrappedValue == .afterInactivity {
                Text("Inactivity uses real keyboard and mouse idle time, not time since unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            if let backupStatus = viewModel.backupStatus {
                Text(backupStatus)
                    .font(.caption)
                    .foregroundStyle(viewModel.backupIsError ? .red : .secondary)
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
            if viewModel.settings.developerMode {
                enforcementSection
            }
            Button("Replay setup guide…") {
                NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
            }
        }
    }

    private var enforcementSection: some View {
        Group {
            Divider()
            Text("Endpoint Security (Phase 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                """
                System Extensions (Endpoint Security AUTH_EXEC) are the supported \
                path for kernel-held launch denial. Classic kernel extensions (kexts) \
                are deprecated and not used. Shipping builds still use overlays unless \
                Apple grants the ES entitlement and the extension is embedded.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            LabeledContent("Extension embedded") {
                Text(systemExtensionRegistrar.isExtensionEmbedded ? "Yes" : "No")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Registration") {
                Text(systemExtensionRegistrar.status.displayText)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack {
                Button("Activate system extension…") {
                    systemExtensionRegistrar.activate()
                }
                .disabled(systemExtensionRegistrar.status == .submitting)
                Button("Deactivate") {
                    systemExtensionRegistrar.deactivate()
                }
                .disabled(systemExtensionRegistrar.status == .submitting)
            }
            Text(
                """
                Build with EMBED_SYSTEM_EXTENSION=1 Scripts/build-app.sh, sign with \
                host + ES entitlements, grant Full Disk Access, then activate. Admins \
                can still uninstall. See docs/ENFORCEMENT.md.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    private var relockPolicy: Binding<RelockPolicy> {
        viewModel.binding(\.defaultRelockPolicy)
    }

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
            viewModel.setBackupStatus("Exported to \(url.lastPathComponent).", isError: false)
        } catch {
            viewModel.setBackupStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.importConfiguration(from: url)
            viewModel.setBackupStatus("Imported from \(url.lastPathComponent).", isError: false)
        } catch {
            viewModel.setBackupStatus("Import failed: \(error.localizedDescription)", isError: true)
        }
    }
}
