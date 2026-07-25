//
//  MainView.swift
//  FreshLock
//
//  Main window: native macOS materials, segmented filter, inset list. Chrome
//  optionally uses Liquid Glass when preferred and the OS supports it.
//

import FreshLockCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: ProtectionViewModel

    private var preferGlass: Bool {
        viewModel.configuration.settings.preferLiquidGlass
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            list
        }
        .background(Theme.windowBackground)
        .tint(Theme.accent)
        .environment(\.preferLiquidGlass, preferGlass)
        .frame(minWidth: 560, minHeight: 520)
        .task { await viewModel.refreshInstalledApps() }
        .onAppear {
            Task { await viewModel.refreshInstalledApps() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    Text("FreshLock")
                        .font(.title2.weight(.semibold))
                }
                Spacer(minLength: 8)
                Text("\(viewModel.protectedCount) protected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    WindowManager.shared.showPreferences()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Preferences")
                .accessibilityLabel("Preferences")
            }

            searchField

            Picker("Filter", selection: $viewModel.sidebarSelection) {
                Text("All").tag(SidebarItem.all)
                Text("Protected").tag(SidebarItem.protected)
                Text("Favorites").tag(SidebarItem.favorites)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .freshLockGlass(enabled: preferGlass, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: List

    private var list: some View {
        Group {
            if viewModel.isLoadingCatalogue, viewModel.installedApps.isEmpty {
                ProgressView("Scanning applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleApps.isEmpty {
                emptyState
            } else {
                List(viewModel.visibleApps) { app in
                    AppRowView(viewModel: viewModel, app: app)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.isCatalogueEmpty ? "No Applications" : "No Matches",
                systemImage: viewModel.isCatalogueEmpty ? "app.dashed" : "magnifyingglass"
            )
        } description: {
            if viewModel.isCatalogueEmpty {
                Text(viewModel.catalogueError ?? "Check /Applications and try again.")
            } else if viewModel.isFilterEmpty {
                Text("Try clearing search or switching to All.")
            } else {
                Text("No apps match.")
            }
        } actions: {
            if viewModel.isCatalogueEmpty {
                Button("Scan Again") {
                    Task { await viewModel.refreshInstalledApps() }
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.isFilterEmpty {
                Button("Show All Apps") {
                    viewModel.searchText = ""
                    viewModel.sidebarSelection = .all
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
