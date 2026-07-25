//
//  AppDetailView.swift
//  AppLock
//
//  The per-app inspector shown when an app is selected in the list. It exposes
//  everything configurable about a single `ProtectedApp`: protection, favourite,
//  category, its relock policy (overriding the global default), and the
//  terminate-after-failures limit.
//

import AppLockCore
import SwiftUI

struct AppDetailView: View {
    @ObservedObject var viewModel: ProtectionViewModel
    let app: InstalledApp

    var body: some View {
        Form {
            header

            Section("Protection") {
                Toggle("Protect this app", isOn: protectionBinding)
                Toggle("Favourite", isOn: favoriteBinding)
                Picker("Category", selection: categoryBinding) {
                    ForEach(AppCategory.allCases, id: \.self) { category in
                        Label(category.displayName, systemImage: category.symbolName).tag(category)
                    }
                }
            }

            Section("Auto Relock") {
                Picker("Relock", selection: policyKindBinding) {
                    Text("Default (\(viewModel.defaultRelockPolicy.editorLabel))").tag(PolicyKind.useDefault)
                    ForEach(PolicyKind.explicitCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                if policyKindBinding.wrappedValue.needsMinutes {
                    Stepper("After \(minutesBinding.wrappedValue) min", value: minutesBinding, in: 1...240)
                }
            }

            Section {
                Toggle("Quit after repeated failures", isOn: terminateEnabledBinding)
                if let limit = currentEntry?.terminateAfterFailures {
                    Stepper("After \(limit) failed attempts", value: terminateLimitBinding, in: 1...10)
                }
            } footer: {
                Text("If authentication fails this many times in a row, AppLock will quit the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            app.iconImage.resizable().frame(width: 48, height: 48).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(app.name).font(.title3.weight(.semibold))
                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Model access

    private var currentEntry: ProtectedApp? { viewModel.protectedApp(for: app.bundleIdentifier) }

    // MARK: Bindings

    private var protectionBinding: Binding<Bool> {
        .init(get: { viewModel.isProtected(app.bundleIdentifier) },
              set: { _ in viewModel.toggleProtection(for: app) })
    }

    private var favoriteBinding: Binding<Bool> {
        .init(get: { viewModel.isFavorite(app.bundleIdentifier) },
              set: { _ in viewModel.toggleFavorite(for: app) })
    }

    private var categoryBinding: Binding<AppCategory> {
        .init(get: { currentEntry?.category ?? .other },
              set: { viewModel.setCategory($0, for: app) })
    }

    private var policyKindBinding: Binding<PolicyKind> {
        .init(
            get: { PolicyKind(from: currentEntry?.relockPolicy) },
            set: { kind in
                viewModel.setRelockPolicy(kind.makePolicy(minutes: minutesBinding.wrappedValue), for: app)
            }
        )
    }

    private var minutesBinding: Binding<Int> {
        .init(
            get: { currentEntry?.relockPolicy?.minutes ?? 5 },
            set: { newMinutes in
                let kind = PolicyKind(from: currentEntry?.relockPolicy)
                viewModel.setRelockPolicy(kind.makePolicy(minutes: newMinutes), for: app)
            }
        )
    }

    private var terminateEnabledBinding: Binding<Bool> {
        .init(
            get: { currentEntry?.terminateAfterFailures != nil },
            set: { on in viewModel.setTerminateAfterFailures(on ? 3 : nil, for: app) }
        )
    }

    private var terminateLimitBinding: Binding<Int> {
        .init(
            get: { currentEntry?.terminateAfterFailures ?? 3 },
            set: { viewModel.setTerminateAfterFailures($0, for: app) }
        )
    }
}
