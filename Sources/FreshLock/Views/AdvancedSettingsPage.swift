//
//  AdvancedSettingsPage.swift
//  FreshLock
//
//  Permissions, developer mode, and the Endpoint Security controls that only
//  appear once developer mode is on.
//

import FreshLockCore
import FreshLockEngine
import SwiftUI

struct AdvancedSettingsPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var systemExtensionRegistrar = SystemExtensionRegistrar()

    var body: some View {
        SettingsSection(title: "Permissions") {
            SettingsCard {
                SettingsRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    subtitle: """
                    Required for reliable locking. Enable FreshLock under \
                    Privacy & Security > Accessibility.
                    """
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
}
