//
//  AppRowView.swift
//  FreshLock
//
//  A single app row: icon, name, favourite, options popover, protection switch.
//  Surfaces use system materials or Liquid Glass based on preference.
//

import FreshLockCore
import SwiftUI

struct AppRowView: View {
    @ObservedObject var viewModel: ProtectionViewModel
    let app: InstalledApp

    @State private var hovering = false
    @State private var showOptions = false

    private var isProtected: Bool {
        viewModel.isProtected(app.bundleIdentifier)
    }

    private var isFavorite: Bool {
        viewModel.isFavorite(app.bundleIdentifier)
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(hovering ? 0.55 : 0.35), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(
                    isProtected
                        ? Theme.protected.opacity(0.45)
                        : Theme.separator.opacity(hovering ? 0.7 : 0.35),
                    lineWidth: 1
                )
        }
        .onHover { hovering = $0 }
    }

    private var icon: some View {
        app.iconImage
            .resizable()
            .frame(width: 36, height: 36)
            .overlay(alignment: .bottomTrailing) {
                if isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Theme.protected, in: Circle())
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.toggleFavorite(for: app)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")

            Button {
                showOptions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Options")
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                AppOptionsPopover(viewModel: viewModel, app: app)
            }

            Toggle("", isOn: Binding(
                get: { isProtected },
                set: { _ in viewModel.toggleProtection(for: app) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Protect \(app.name)")
        }
    }
}

/// Per-app options: relock policy and terminate-after-failures.
private struct AppOptionsPopover: View {
    @ObservedObject var viewModel: ProtectionViewModel
    let app: InstalledApp

    private var entry: ProtectedApp? {
        viewModel.protectedApp(for: app.bundleIdentifier)
    }

    var body: some View {
        Form {
            Text(app.name).font(.headline)

            Picker("Auto Relock", selection: policyKind) {
                Text("Default (\(viewModel.defaultRelockPolicy.editorLabel))").tag(PolicyKind.useDefault)
                ForEach(PolicyKind.explicitCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if policyKind.wrappedValue.needsMinutes {
                Stepper("After \(minutes.wrappedValue) min", value: minutes, in: 1 ... 240)
            }

            Toggle("Quit after repeated failures", isOn: terminateEnabled)
            if entry?.terminateAfterFailures != nil {
                Stepper("After \(terminateLimit.wrappedValue) attempts", value: terminateLimit, in: 1 ... 10)
            }
        }
        .formStyle(.grouped)
        .frame(width: 280)
        .padding(4)
    }

    private var policyKind: Binding<PolicyKind> {
        .init(
            get: { PolicyKind(from: entry?.relockPolicy) },
            set: { viewModel.setRelockPolicy($0.makePolicy(minutes: minutes.wrappedValue), for: app) }
        )
    }

    private var minutes: Binding<Int> {
        .init(
            get: { entry?.relockPolicy?.minutes ?? 5 },
            set: { viewModel.setRelockPolicy(PolicyKind(from: entry?.relockPolicy).makePolicy(minutes: $0), for: app) }
        )
    }

    private var terminateEnabled: Binding<Bool> {
        .init(
            get: { entry?.terminateAfterFailures != nil },
            set: { viewModel.setTerminateAfterFailures($0 ? 3 : nil, for: app) }
        )
    }

    private var terminateLimit: Binding<Int> {
        .init(
            get: { entry?.terminateAfterFailures ?? 3 },
            set: { viewModel.setTerminateAfterFailures($0, for: app) }
        )
    }
}
