//
//  OnboardingView.swift
//  FreshLock
//
//  First-launch setup guide. Native macOS materials / Liquid Glass chrome,
//  teal brand accent, real app icon - not a centered SF Symbol wizard.
//  Accessibility remains a hard gate; copy wraps without clipping.
//

import AppKit
import FreshLockCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.preferLiquidGlass) private var preferGlass

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandChrome
                        .padding(.bottom, 28)

                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(pageTransition)
                        .id(viewModel.step)
                }
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .background(Theme.windowBackground)
        .tint(Theme.accent)
        .frame(minWidth: 540, idealWidth: 580, minHeight: 520, idealHeight: 600)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: viewModel.step)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        // Forward: new page enters from the right; Back: from the left.
        switch viewModel.navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    // MARK: Brand chrome

    /// Compact lockup shared across pages - real app icon, no icon-in-tile.
    private var brandChrome: some View {
        HStack(alignment: .center, spacing: 12) {
            AppBrandIcon(size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("FreshLock")
                    .font(.headline)
                Text(stepCaption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var stepCaption: String {
        switch viewModel.step {
        case .welcome: "Setup"
        case .accessibility: "Step 2 of 4 · Accessibility"
        case .launchAtLogin: "Step 3 of 4 · Launch at login"
        case .done: "Step 4 of 4 · Ready"
        }
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .welcome: welcomePage
        case .accessibility: accessibilityPage
        case .launchAtLogin: launchAtLoginPage
        case .done: donePage
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle(
                "Protect apps with Touch ID",
                subtitle: "Safari, Finder, System Settings - unlock with Apple's authentication. FreshLock never sees your password."
            )

            VStack(alignment: .leading, spacing: 14) {
                featureRow("lock.fill", "Lock any app you choose")
                featureRow("touchid", "Touch ID, Apple Watch, or Mac password")
                featureRow("bolt.fill", "Notification-driven; near-zero idle CPU")
            }

            honestNote
        }
    }

    private var accessibilityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle(
                "Allow Accessibility",
                subtitle: "FreshLock uses Accessibility to detect protected windows and cover them without interrupting Touch ID."
            )

            statusPanel

            if !viewModel.accessibilityTrusted {
                Button("Open System Settings…") {
                    viewModel.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Continue stays disabled until Accessibility is granted. After enabling FreshLock in System Settings, return here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You can change this later in System Settings → Privacy & Security → Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { viewModel.refreshAccessibilityStatus() }
    }

    private var launchAtLoginPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle(
                "Keep protecting after restart",
                subtitle: "Launch FreshLock at login so locked apps stay covered when you sign back in."
            )

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch FreshLock at login", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .font(.body.weight(.medium))

                Text("You can change this anytime in Preferences.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .freshLockGlass(
                enabled: preferGlass,
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            )
        }
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle(
                "You're all set",
                subtitle: "Open FreshLock from the menu bar to choose which apps to protect."
            )

            featureRow("menubar.arrow.up.rectangle", "Find FreshLock in the menu bar for quick actions.")
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .freshLockGlass(
                    enabled: preferGlass,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                )
        }
    }

    // MARK: Shared pieces

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Limits callout as a proper surface - not dim fine print.
    private var honestNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Honest about the limits")
                .font(.subheadline.weight(.semibold))
            Text(
                """
                macOS has no public way to block an app from launching. FreshLock \
                covers a protected app the instant it opens and requires authentication - \
                a strong deterrent, not OS-enforced security.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .freshLockGlass(
            enabled: preferGlass,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.accessibilityTrusted
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(viewModel.accessibilityTrusted ? Theme.protected : Color.orange)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.accessibilityTrusted
                    ? "Accessibility is enabled"
                    : "Accessibility is required for app locking")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !viewModel.accessibilityTrusted {
                    Text("Turn on FreshLock in the Accessibility list, then come back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .freshLockGlass(
            enabled: preferGlass,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.accessibilityTrusted
            ? "Accessibility is enabled"
            : "Accessibility is required for app locking")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if viewModel.canGoBack {
                Button("Back") { viewModel.back() }
                    .buttonStyle(.borderless)
                    .controlSize(.large)
            }

            Spacer(minLength: 8)

            StepIndicator(
                count: OnboardingViewModel.Step.allCases.count,
                index: viewModel.step.rawValue,
                reduceMotion: reduceMotion
            )

            Spacer(minLength: 8)

            if viewModel.isLastStep {
                Button("Done") { viewModel.finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { viewModel.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canContinue)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.bar)
    }

}

// MARK: - Step indicator

/// Segmented progress: active step is a short capsule, others are quiet dots.
private struct StepIndicator: View {
    let count: Int
    let index: Int
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == index ? Theme.accent : Color.secondary.opacity(0.28))
                    .frame(width: i == index ? 18 : 7, height: 7)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
