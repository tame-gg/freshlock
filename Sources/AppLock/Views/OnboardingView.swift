//
//  OnboardingView.swift
//  AppLock
//
//  The first-launch setup guide. A compact, paged flow that primes the two
//  permissions AppLock benefits from and — importantly — states plainly what
//  AppLock is (a deterrent built on public APIs) and is not (OS-enforced).
//

import AppLockCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(viewModel.step)

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 520, height: 460)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.step)
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .welcome: welcomePage
        case .launchAtLogin: launchAtLoginPage
        case .done: donePage
        }
    }

    private var welcomePage: some View {
        pageScaffold(
            icon: "lock.shield.fill",
            title: "Welcome to AppLock",
            subtitle: "Protect any app behind Touch ID, Apple Watch, or your Mac password."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                bullet("lock.fill", "Lock apps like Safari, Finder or System Settings.")
                bullet("faceid", "Unlock with Apple's own authentication — AppLock never sees your password.")
                bullet("bolt.fill", "Lightweight and notification-driven; near-zero idle CPU.")

                Text("Honest note: macOS has no public way to *block* an app from launching. AppLock covers a protected app the instant it opens and requires authentication — a strong deterrent, not OS-enforced security.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var launchAtLoginPage: some View {
        pageScaffold(
            icon: "power",
            title: "Keep Protecting",
            subtitle: "Launch AppLock at login so your apps stay protected after every restart."
        ) {
            Toggle("Launch AppLock at login", isOn: Binding(
                get: { viewModel.launchAtLoginEnabled },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .padding(.vertical, 8)
        }
    }

    private var donePage: some View {
        pageScaffold(
            icon: "checkmark.seal.fill",
            title: "You're all set",
            subtitle: "Open AppLock from the menu bar to choose which apps to protect."
        ) {
            bullet("menubar.arrow.up.rectangle", "Find AppLock in your menu bar for quick actions.")
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
            }
        }
    }

    // MARK: Building blocks

    private func pageScaffold<Body: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            body()
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text)
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
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
