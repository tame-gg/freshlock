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
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 660)
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
            Toggle("Relock when switching away (all apps)", isOn: viewModel.binding(\.requireEveryLaunch))
                .help("Paranoid mode: always require authentication again after leaving a protected app, regardless of that app's relock policy. Unlock still sticks while you stay in the app.")
            Text(
                """
                Applies `.afterSwitchingAway` globally. Unlock still sticks while the \
                protected app stays frontmost; quitting always clears unlock.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Toggle(
                "Prompt authentication automatically",
                isOn: viewModel.binding(\.automaticallyPromptAuthentication)
            )
            .help(
                "When on, Touch ID / password appears as soon as you enter a protected app. When off, only the lock overlay appears until you click Unlock."
            )
            Text(
                """
                When off, FreshLock shows the lock overlay only. Click Unlock to \
                authenticate. Cancel returns to the overlay.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            GracePeriodEditor(seconds: viewModel.binding(\.gracePeriodSeconds))
            Text("Time before relock when switching away.")
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
                Text("Required for reliable locking. Enable the FreshLock entry for this app in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("If a FreshLock toggle is already on, it may be a different build. Remove old entries and enable:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AccessibilityPermission.runningBundlePathDisplay)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
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
