//
//  PreferencesView.swift
//  FreshLock
//
//  Embeddable Settings content: one native grouped Form per `SettingsPane`,
//  shown in the main window's detail pane. Splitting the pages keeps each one
//  short enough to read, and lets the explanatory copy live as a caption under
//  the control it belongs to rather than as loose paragraphs in the scroll.
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
            if pane == .about {
                aboutPane
            } else {
                form
            }
        }
        .tint(Theme.accent)
        .environment(\.preferLiquidGlass, preferGlass)
    }

    private var form: some View {
        Form {
            switch pane {
            case .general:
                generalSection
                appearanceSection
            case .locking:
                lockingSection
            case .shortcuts:
                shortcutsSection
            case .backup:
                backupSection
            case .advanced:
                advancedSection
            case .about:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            Toggle(isOn: viewModel.launchAtLogin) {
                SettingsRowLabel(
                    symbol: "power",
                    tint: Theme.tileGreen,
                    title: "Launch at login",
                    subtitle: "Start protecting apps as soon as you sign in."
                )
            }
            if let error = viewModel.loginItemError {
                SettingsRowNote(text: "\(error)", isError: true)
            }

            Toggle(isOn: viewModel.showMenuBarIcon) {
                SettingsRowLabel(
                    symbol: "menubar.rectangle",
                    tint: Theme.tileGray,
                    title: "Show icon in menu bar",
                    subtitle: "Lock state and your protected apps, one click away."
                )
            }
            if !viewModel.showMenuBarIcon.wrappedValue {
                SettingsRowNote(text: "Reopen FreshLock from Finder or Spotlight to bring back its window.")
            }

            Toggle(isOn: viewModel.binding(\.notifyOnProtectedLaunch)) {
                SettingsRowLabel(
                    symbol: "bell.fill",
                    tint: Theme.tileOrange,
                    title: "Notify when a protected app launches",
                    subtitle: "A quiet confirmation that FreshLock stepped in."
                )
            }

            Picker(selection: viewModel.binding(\.overlayStyle)) {
                ForEach(OverlayStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                SettingsRowLabel(
                    symbol: "rectangle.on.rectangle",
                    tint: Theme.tileIndigo,
                    title: "Overlay style",
                    subtitle: "What covers a locked app while it waits for you."
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            // Remains enabled on older OS so the preference persists; glass is a
            // no-op until macOS 26+ (see LiquidGlass.swift).
            Toggle(isOn: viewModel.binding(\.preferLiquidGlass)) {
                SettingsRowLabel(
                    symbol: "circle.lefthalf.filled",
                    tint: Theme.tilePurple,
                    title: "Use Liquid Glass",
                    subtitle: "Opt FreshLock's own surfaces into the system glass material."
                )
            }
            if !LiquidGlassSupport.isAvailable {
                SettingsRowNote(text: LiquidGlassSupport.unavailableNote)
            }
        }
    }

    // MARK: Locking

    private var lockingSection: some View {
        Section("Relock") {
            Picker(selection: defaultRelockKind) {
                ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                SettingsRowLabel(
                    symbol: "clock.arrow.circlepath",
                    tint: Theme.tileBlue,
                    title: "Default relock",
                    subtitle: "\"When switching away\" matches iOS - it re-asks each time you return."
                )
            }
            if defaultRelockKind.wrappedValue.needsMinutes {
                Stepper("Minutes: \(defaultRelockMinutes.wrappedValue)", value: defaultRelockMinutes, in: 1 ... 240)
            }
            if defaultRelockKind.wrappedValue == .afterInactivity {
                SettingsRowNote(text: "Inactivity uses real keyboard and mouse idle time, not time since unlock.")
            }

            Toggle(isOn: viewModel.binding(\.requireEveryLaunch)) {
                SettingsRowLabel(
                    symbol: "arrow.uturn.backward",
                    tint: Theme.tileOrange,
                    title: "Relock when switching away (all apps)",
                    subtitle: """
                    Paranoid mode: applies to every app regardless of its own policy. \
                    Unlock still sticks while you stay in the app; quitting always clears it.
                    """
                )
            }

            Toggle(isOn: viewModel.binding(\.automaticallyPromptAuthentication)) {
                SettingsRowLabel(
                    symbol: "touchid",
                    tint: Theme.tilePink,
                    title: "Prompt authentication automatically",
                    subtitle: """
                    On: Touch ID appears the moment you enter a protected app. \
                    Off: the overlay waits until you click Unlock.
                    """
                )
            }

            GracePeriodEditor(seconds: viewModel.binding(\.gracePeriodSeconds))
            SettingsRowNote(text: "Time before relock when switching away.")
        }
    }

    // MARK: Shortcuts

    private var shortcutsSection: some View {
        Section {
            LabeledContent {
                ShortcutRecorderView(shortcut: viewModel.binding(\.lockAllShortcut))
                    .frame(width: 150, height: 26)
            } label: {
                SettingsRowLabel(symbol: "lock.fill", tint: Theme.tileGreen, title: "Lock All")
            }
            LabeledContent {
                ShortcutRecorderView(shortcut: viewModel.binding(\.unlockAllShortcut))
                    .frame(width: 150, height: 26)
            } label: {
                SettingsRowLabel(symbol: "lock.open.fill", tint: Theme.tileTeal, title: "Unlock All")
            }
        } header: {
            Text("Global Shortcuts")
        } footer: {
            Text("Each shortcut needs at least one of ⌘/⌥/⌃. Press ⌫ while recording to clear.")
        }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section {
            Button(action: exportConfiguration) {
                Label("Export configuration…", systemImage: "square.and.arrow.up")
            }
            Button(action: importConfiguration) {
                Label("Import configuration…", systemImage: "square.and.arrow.down")
            }
            if let backupStatus = viewModel.backupStatus {
                Text(backupStatus)
                    .font(.caption)
                    .foregroundStyle(viewModel
                        .backupIsError ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
        } header: {
            Text("Configuration File")
        } footer: {
            Text("A single JSON file with your protected apps and preferences. It never contains passwords.")
        }
    }

    // MARK: Advanced

    @ViewBuilder
    private var advancedSection: some View {
        Section("Permissions") {
            LabeledContent {
                if AccessibilityPermission.isTrusted {
                    Text("Granted")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Open Settings…") {
                        AccessibilityPermission.requestTrust()
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            } label: {
                SettingsRowLabel(
                    symbol: "accessibility",
                    tint: Theme.tileBlue,
                    title: "Accessibility",
                    subtitle: "Required for reliable locking. Enable FreshLock under Privacy & Security → Accessibility."
                )
            }
            if !AccessibilityPermission.isTrusted {
                SettingsRowNote(
                    text: "If a FreshLock toggle is already on, it may be a different build. Remove old entries and enable:"
                )
                Text(AccessibilityPermission.runningBundlePathDisplay)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.tileSideRow + 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        Section("Developer") {
            Toggle(isOn: viewModel.binding(\.developerMode)) {
                SettingsRowLabel(
                    symbol: "hammer.fill",
                    tint: Theme.tileGray,
                    title: "Developer mode",
                    subtitle: "Show the Endpoint Security enforcement controls."
                )
            }
            if viewModel.settings.developerMode {
                enforcementSection
            }
            Button {
                NotificationCenter.default.post(name: OnboardingPresenter.replayNotification, object: nil)
            } label: {
                Label("Replay setup guide…", systemImage: "arrow.counterclockwise")
            }
        }
    }

    @ViewBuilder
    private var enforcementSection: some View {
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
