//
//  PreferencesView.swift
//  FreshLock
//
//  Embeddable Settings content: one page per `SettingsPane`, shown in the main
//  window's detail pane. Pages are built from the grouped cards in SettingsKit
//  rather than a `Form`, which buys roomier rows and lets a single control sit
//  on its own island. Explanatory copy lives under the control it belongs to
//  instead of as loose paragraphs in the scroll.
//

import AppKit
import FreshLockCore
import FreshLockEngine
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var pane: SettingsPane = .general

    @StateObject private var systemExtensionRegistrar = SystemExtensionRegistrar()

    private var preferGlass: Bool {
        viewModel.settings.preferLiquidGlass
    }

    var body: some View {
        Group {
            switch pane {
            case .about:
                aboutPane
            case .general:
                SettingsPageBody { generalPage }
            case .locking:
                SettingsPageBody { lockingPage }
            case .shortcuts:
                SettingsPageBody { shortcutsPage }
            case .backup:
                SettingsPageBody { backupPage }
            case .advanced:
                SettingsPageBody { advancedPage }
            }
        }
        .tint(Theme.accent)
        .environment(\.preferLiquidGlass, preferGlass)
    }

    // MARK: General

    @ViewBuilder
    private var generalPage: some View {
        SettingsSection(title: "Startup") {
            SettingsCard {
                SettingsRow(
                    symbol: "power",
                    title: "Launch at login",
                    subtitle: "Start protecting apps as soon as you sign in."
                ) {
                    Toggle("", isOn: viewModel.launchAtLogin).labelsHidden()
                }
            }
            if let error = viewModel.loginItemError {
                SettingsFootnote(text: "\(error)", isError: true)
            }
        }

        SettingsSection(title: "Menu Bar") {
            SettingsCard {
                SettingsRow(
                    symbol: "menubar.rectangle",
                    title: "Show icon in menu bar",
                    subtitle: "Lock state and your protected apps, one click away."
                ) {
                    Toggle("", isOn: viewModel.showMenuBarIcon).labelsHidden()
                }
                CardDivider()
                SettingsRow(
                    symbol: "bell.fill",
                    title: "Notify when a protected app launches",
                    subtitle: "A quiet confirmation that FreshLock stepped in."
                ) {
                    Toggle("", isOn: viewModel.binding(\.notifyOnProtectedLaunch)).labelsHidden()
                }
            }
            if !viewModel.showMenuBarIcon.wrappedValue {
                SettingsFootnote(text: "Reopen FreshLock from Finder or Spotlight to bring back its window.")
            }
        }

        SettingsSection(title: "Appearance") {
            SettingsCard {
                SettingsRow(
                    symbol: "rectangle.on.rectangle",
                    title: "Overlay style",
                    subtitle: "What covers a locked app while it waits for you."
                ) {
                    Picker("", selection: viewModel.binding(\.overlayStyle)) {
                        ForEach(OverlayStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsCard {
                // Remains enabled on older OS so the preference persists; glass
                // is a no-op until macOS 26+ (see LiquidGlass.swift).
                SettingsRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Use Liquid Glass",
                    subtitle: "Opt FreshLock's own surfaces into the system glass material."
                ) {
                    Toggle("", isOn: viewModel.binding(\.preferLiquidGlass)).labelsHidden()
                }
            }
            if !LiquidGlassSupport.isAvailable {
                SettingsFootnote(text: LiquidGlassSupport.unavailableNote)
            }
        }
    }

    // MARK: Locking

    @ViewBuilder
    private var lockingPage: some View {
        SettingsSection(title: "Relock") {
            SettingsCard {
                SettingsRow(
                    symbol: "clock.arrow.circlepath",
                    title: "Default relock",
                    subtitle: "\"When switching away\" matches iOS - it re-asks each time you return."
                ) {
                    Picker("", selection: defaultRelockKind) {
                        ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if defaultRelockKind.wrappedValue.needsMinutes {
                    CardContinuation {
                        Stepper(
                            "Minutes: \(defaultRelockMinutes.wrappedValue)",
                            value: defaultRelockMinutes,
                            in: 1 ... 240
                        )
                        .font(.system(size: 12))
                    }
                }
            }
            if defaultRelockKind.wrappedValue == .afterInactivity {
                SettingsFootnote(text: "Inactivity uses real keyboard and mouse idle time, not time since unlock.")
            }

            SettingsCard {
                SettingsRow(
                    symbol: "arrow.uturn.backward",
                    title: "Relock when switching away (all apps)",
                    subtitle: """
                    Paranoid mode: applies to every app regardless of its own policy. \
                    Unlock still sticks while you stay in the app; quitting always clears it.
                    """
                ) {
                    Toggle("", isOn: viewModel.binding(\.requireEveryLaunch)).labelsHidden()
                }
            }
        }

        SettingsSection(title: "Authentication") {
            SettingsCard {
                SettingsRow(
                    symbol: "touchid",
                    title: "Prompt automatically",
                    subtitle: """
                    On: Touch ID appears the moment you enter a protected app. \
                    Off: the overlay waits until you click Unlock.
                    """
                ) {
                    Toggle("", isOn: viewModel.binding(\.automaticallyPromptAuthentication)).labelsHidden()
                }
                CardDivider()
                SettingsRow(
                    symbol: "hourglass",
                    title: "Grace period",
                    subtitle: "Time before relock when switching away."
                ) {
                    GracePeriodEditor(seconds: viewModel.binding(\.gracePeriodSeconds))
                        .labelsHidden()
                        .fixedSize()
                }
            }
        }
    }

    // MARK: Shortcuts

    private var shortcutsPage: some View {
        SettingsSection(title: "Global Shortcuts") {
            SettingsCard {
                SettingsRow(symbol: "lock.fill", title: "Lock All") {
                    ShortcutRecorderView(shortcut: viewModel.binding(\.lockAllShortcut))
                        .frame(width: 150, height: 24)
                }
                CardDivider()
                SettingsRow(symbol: "lock.open.fill", title: "Unlock All") {
                    ShortcutRecorderView(shortcut: viewModel.binding(\.unlockAllShortcut))
                        .frame(width: 150, height: 24)
                }
            }
            SettingsFootnote(text: "Each shortcut needs at least one of ⌘/⌥/⌃. Press ⌫ while recording to clear.")
        }
    }

    // MARK: Backup

    private var backupPage: some View {
        SettingsSection(title: "Configuration File") {
            SettingsCard {
                SettingsActionRow(
                    symbol: "square.and.arrow.up",
                    title: "Export configuration…",
                    subtitle: "Save your protected apps and preferences to a JSON file.",
                    action: exportConfiguration
                )
                CardDivider()
                SettingsActionRow(
                    symbol: "square.and.arrow.down",
                    title: "Import configuration…",
                    subtitle: "Replace the current setup with a saved file.",
                    action: importConfiguration
                )
            }
            if let backupStatus = viewModel.backupStatus {
                SettingsFootnote(text: "\(backupStatus)", isError: viewModel.backupIsError)
            }
            SettingsFootnote(text: "The file never contains passwords.")
        }
    }

    // MARK: Advanced

    @ViewBuilder
    private var advancedPage: some View {
        SettingsSection(title: "Permissions") {
            SettingsCard {
                SettingsRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    subtitle: "Required for reliable locking. Enable FreshLock under Privacy & Security → Accessibility."
                ) {
                    if AccessibilityPermission.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.protected)
                    } else {
                        Button("Open Settings…") {
                            AccessibilityPermission.requestTrust()
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }
                if !AccessibilityPermission.isTrusted {
                    CardContinuation {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                """
                                If a FreshLock toggle is already on, it may be a different build. \
                                Remove old entries and enable:
                                """
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Text(AccessibilityPermission.runningBundlePathDisplay)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        SettingsSection(title: "Developer") {
            SettingsCard {
                SettingsRow(
                    symbol: "hammer.fill",
                    title: "Developer mode",
                    subtitle: "Show the Endpoint Security enforcement controls."
                ) {
                    Toggle("", isOn: viewModel.binding(\.developerMode)).labelsHidden()
                }
                CardDivider()
                SettingsActionRow(
                    symbol: "arrow.counterclockwise",
                    title: "Replay setup guide…",
                    subtitle: "Walk through first-run permissions again."
                ) {
                    NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
                }
            }
        }

        if viewModel.settings.developerMode {
            enforcementSection
        }
    }

    private var enforcementSection: some View {
        SettingsSection(title: "Endpoint Security (Phase 1)") {
            SettingsCard {
                SettingsRow(symbol: "shield.lefthalf.filled", title: "Extension embedded") {
                    Text(systemExtensionRegistrar.isExtensionEmbedded ? "Yes" : "No")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                CardDivider()
                SettingsRow(symbol: "checkmark.seal", title: "Registration") {
                    Text(systemExtensionRegistrar.status.displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
                CardDivider()
                CardContinuation {
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
                    .padding(.top, 12)
                }
            }
            SettingsFootnote(
                text: """
                System Extensions (Endpoint Security AUTH_EXEC) are the supported path for kernel-held launch \
                denial; kexts are deprecated and not used. Build with EMBED_SYSTEM_EXTENSION=1 \
                Scripts/build-app.sh, sign with host + ES entitlements, grant Full Disk Access, then activate. \
                See docs/ENFORCEMENT.md.
                """
            )
        }
    }

    // MARK: About

    private var aboutPane: some View {
        ScrollView {
            AboutView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
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
