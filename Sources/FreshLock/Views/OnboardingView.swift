//
//  OnboardingView.swift
//  FreshLock
//
//  The first-launch setup guide. A compact, paged flow that primes Accessibility
//  (required for window covering), offers launch-at-login, and - importantly -
//  states plainly what FreshLock is (a deterrent built on public APIs) and is not
//  (OS-enforced).
//

import FreshLockCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(viewModel.step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 580)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.step)
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
        pageScaffold(
            icon: "lock.shield.fill",
            title: "Welcome to FreshLock",
            subtitle: "Protect any app behind Touch ID, Apple Watch, or your Mac password."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                bullet("lock.fill", "Lock apps like Safari, Finder or System Settings.")
                bullet("faceid", "Unlock with Apple's own authentication - FreshLock never sees your password.")
                bullet("bolt.fill", "Lightweight and notification-driven; near-zero idle CPU.")

                Text(
                    """
                    Honest note: macOS has no public way to *block* an app from launching. \
                    FreshLock covers a protected app the instant it opens and requires \
                    authentication - a strong deterrent, not OS-enforced security.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accessibilityPage: some View {
        pageScaffold(
            icon: "accessibility",
            title: "Allow Accessibility",
            subtitle:
                """
                FreshLock uses Accessibility to detect protected windows and cover \
                them without interrupting Touch ID.
                """
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: viewModel.accessibilityTrusted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.accessibilityTrusted ? .green : .orange)
                        .padding(.top, 2)
                    Text(viewModel.accessibilityTrusted
                        ? "Accessibility is enabled"
                        : "Accessibility is required for app locking")
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !viewModel.accessibilityTrusted {
                    Button("Open System Settings…") {
                        viewModel.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text(
                        """
                        Continue stays disabled until Accessibility is granted. \
                        After enabling FreshLock in System Settings, return here.
                        """
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("You can change this later in System Settings → Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { viewModel.refreshAccessibilityStatus() }
        }
    }

    private var launchAtLoginPage: some View {
        pageScaffold(
            icon: "power",
            title: "Keep Protecting",
            subtitle: "Launch FreshLock at login so your apps stay protected after every restart."
        ) {
            Toggle("Launch FreshLock at login", isOn: Binding(
                get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var donePage: some View {
        pageScaffold(
            icon: "checkmark.seal.fill",
            title: "You're all set",
            subtitle: "Open FreshLock from the menu bar to choose which apps to protect."
        ) {
            bullet("menubar.arrow.up.rectangle", "Find FreshLock in your menu bar for quick actions.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if viewModel.canGoBack {
                Button("Back") { viewModel.back() }
            }
            Spacer()
            PageDots(count: OnboardingViewModel.Step.allCases.count, index: viewModel.step.rawValue)
            Spacer()
            if viewModel.isLastStep {
                Button("Done") { viewModel.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { viewModel.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canContinue)
            }
        }
    }

    // MARK: Building blocks

    private func pageScaffold(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder body: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            body()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Simple page indicator dots.
private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
