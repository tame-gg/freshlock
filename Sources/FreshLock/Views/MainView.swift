//
//  MainView.swift
//  FreshLock
//
//  Main window: BetterDisplay-style sidebar + detail. Filters live in a
//  translucent sidebar; the catalogue is an inset grouped list with quiet
//  hierarchy - no loud segmented tabs or per-row card chrome. Settings is a
//  sibling sidebar item that fills the same detail pane.
//

import FreshLockCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: ProtectionViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    private var preferGlass: Bool {
        viewModel.configuration.settings.preferLiquidGlass
    }

    private var settingsPane: SettingsPane? {
        viewModel.sidebarSelection.settingsPane
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .environment(\.preferLiquidGlass, preferGlass)
        .frame(minWidth: 720, minHeight: 520)
        .task { await viewModel.refreshInstalledApps() }
        .onAppear {
            Task { await viewModel.refreshInstalledApps() }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section("Library") {
                ForEach(SidebarItem.primaryCases, id: \.self) { item in
                    Label(item.title, systemImage: item.symbolName)
                        .tag(item)
                }
            }
            Section("Settings") {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(SidebarItem.settings(pane))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: 150,
            ideal: Theme.sidebarWidth,
            max: 240
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                AppBrandIcon(size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FreshLock")
                        .font(.caption.weight(.semibold))
                    Text("\(viewModel.protectedCount) protected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(viewModel.protectedCount) apps protected")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let settingsPane {
            settingsDetail(settingsPane)
        } else {
            catalogueDetail
        }
    }

    private func settingsDetail(_ pane: SettingsPane) -> some View {
        PreferencesView(viewModel: settingsViewModel, pane: pane)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.windowBackground)
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsPageHeader(pane: pane)
            }
            .navigationTitle(pane.title)
    }

    private var catalogueDetail: some View {
        Group {
            if viewModel.isLoadingCatalogue, viewModel.installedApps.isEmpty {
                ProgressView("Scanning applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleApps.isEmpty {
                emptyState
            } else {
                appList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .navigationTitle(viewModel.sidebarSelection.title)
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: "Search apps"
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(viewModel.visibleApps.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(viewModel.visibleApps.count) apps shown")
            }
        }
    }

    private var appList: some View {
        List {
            Section {
                ForEach(viewModel.visibleApps) { app in
                    AppRowView(viewModel: viewModel, app: app)
                }
            } header: {
                Text(sectionHeader)
                    .textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var sectionHeader: String {
        switch viewModel.sidebarSelection {
        case .all:
            return viewModel.searchText.isEmpty ? "Applications" : "Results"
        case .protected:
            return "Protected apps"
        case .favorites:
            return "Favorites"
        case .settings:
            return "Settings"
        case .category(let category):
            return category.displayName
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySymbol)
        } description: {
            Text(emptyDescription)
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

    private var emptyTitle: String {
        if viewModel.isCatalogueEmpty { return "No Applications" }
        if !viewModel.searchText.isEmpty { return "No Matches" }
        switch viewModel.sidebarSelection {
        case .protected: return "Nothing Protected Yet"
        case .favorites: return "No Favorites"
        default: return "No Matches"
        }
    }

    private var emptySymbol: String {
        if viewModel.isCatalogueEmpty { return "app.dashed" }
        if !viewModel.searchText.isEmpty { return "magnifyingglass" }
        switch viewModel.sidebarSelection {
        case .protected: return "lock.open"
        case .favorites: return "star"
        default: return "magnifyingglass"
        }
    }

    private var emptyDescription: String {
        if viewModel.isCatalogueEmpty {
            return viewModel.catalogueError ?? "Check /Applications and try again."
        }
        if !viewModel.searchText.isEmpty {
            return "Try a different search or clear the filter."
        }
        switch viewModel.sidebarSelection {
        case .protected:
            return "Flip the switch on any app in All to protect it behind Touch ID."
        case .favorites:
            return "Star apps you use often so they float to the top of All."
        default:
            return "Try clearing search or switching to All."
        }
    }
}

// MARK: - SidebarItem presentation

extension SidebarItem {
    /// Primary filter rows shown in the main sidebar (above Settings).
    static var primaryCases: [SidebarItem] {
        [.all, .protected, .favorites]
    }

    var title: String {
        switch self {
        case .all: "All"
        case .protected: "Protected"
        case .favorites: "Favorites"
        case .settings(let pane): pane.title
        case .category(let category): category.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .protected: "lock.fill"
        case .favorites: "star.fill"
        case .settings(let pane): pane.symbolName
        case .category(let category): category.symbolName
        }
    }
}
