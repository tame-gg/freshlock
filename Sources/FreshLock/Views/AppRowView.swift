//
//  AppRowView.swift
//  FreshLock
//
//  A single app row in the redesigned list: rounded icon, name, a favourite
//  star, a per-app options popover, and the protection switch. Kept deliberately
//  calm — advanced options are tucked into the popover so the list reads clearly.
//

import FreshLockCore
import SwiftUI

struct AppRowView: View {
    @ObservedObject var viewModel: ProtectionViewModel
    let app: InstalledApp

    @State private var hovering = false
    @State private var showOptions = false

    private var isProtected: Bool { viewModel.isProtected(app.bundleIdentifier) }
    private var isFavorite: Bool { viewModel.isFavorite(app.bundleIdentifier) }

    var body: some View {
        HStack(spacing: 13) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(app.bundleIdentifier)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background((hovering ? Theme.cardHover : Theme.card), in: .rect(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(isProtected ? Theme.green.opacity(0.35) : Theme.stroke))
        .onHover { hovering = $0 }
    }

    private var icon: some View {
        app.iconImage
            .resizable()
            .frame(width: 38, height: 38)
            .overlay(alignment: .bottomTrailing) {
                if isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.base)
                        .padding(3)
                        .background(Theme.green, in: .circle)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            iconButton(isFavorite ? "star.fill" : "star", tint: isFavorite ? Theme.cyan : Theme.textMuted) {
                viewModel.toggleFavorite(for: app)
            }
            .help(isFavorite ? "Remove from favourites" : "Add to favourites")

            iconButton("slider.horizontal.3", tint: Theme.textMuted) { showOptions = true }
                .help("Options")
                .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                    AppOptionsPopover(viewModel: viewModel, app: app)
                }

            Toggle("", isOn: Binding(
                get: { isProtected },
                set: { _ in viewModel.toggleProtection(for: app) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.green)
            .labelsHidden()
            .accessibilityLabel("Protect \(app.name)")
        }
    }

    private func iconButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The per-app options shown in the row's popover: relock policy and the
/// terminate-after-failures limit.
private struct AppOptionsPopover: View {
    @ObservedObject var viewModel: ProtectionViewModel
    let app: InstalledApp

    private var entry: ProtectedApp? { viewModel.protectedApp(for: app.bundleIdentifier) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.name).font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Auto Relock").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: policyKind) {
                    Text("Default (\(viewModel.defaultRelockPolicy.editorLabel))").tag(PolicyKind.useDefault)
                    ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                if policyKind.wrappedValue.needsMinutes {
                    Stepper("After \(minutes.wrappedValue) min", value: minutes, in: 1...240)
                }
            }

            Divider()

            Toggle("Quit after repeated failures", isOn: terminateEnabled)
            if let limit = entry?.terminateAfterFailures {
                Stepper("After \(limit) attempts", value: terminateLimit, in: 1...10)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // Bindings (mirror AppDetailView's, kept local to the popover).
    private var policyKind: Binding<PolicyKind> {
        .init(get: { PolicyKind(from: entry?.relockPolicy) },
              set: { viewModel.setRelockPolicy($0.makePolicy(minutes: minutes.wrappedValue), for: app) })
    }
    private var minutes: Binding<Int> {
        .init(get: { entry?.relockPolicy?.minutes ?? 5 },
              set: { viewModel.setRelockPolicy(PolicyKind(from: entry?.relockPolicy).makePolicy(minutes: $0), for: app) })
    }
    private var terminateEnabled: Binding<Bool> {
        .init(get: { entry?.terminateAfterFailures != nil },
              set: { viewModel.setTerminateAfterFailures($0 ? 3 : nil, for: app) })
    }
    private var terminateLimit: Binding<Int> {
        .init(get: { entry?.terminateAfterFailures ?? 3 },
              set: { viewModel.setTerminateAfterFailures($0, for: app) })
    }
}
