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
            Section {
                ForEach(SidebarItem.primaryCases, id: \.self) { item in
                    sidebarRow(symbol: item.symbolName, title: item.title)
                        .tag(item)
                }
            } header: {
                sidebarSectionHeader("Library")
            }
            Section {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarRow(symbol: pane.symbolName, title: pane.title)
                        .tag(SidebarItem.settings(pane))
                }
            } header: {
                sidebarSectionHeader("Settings")
            }
        }
        .listStyle(.sidebar)
        // Neutral selection keeps the tinted wells as the only colour in the
        // column; an accent-filled pill fights them for attention.
        .tint(Theme.sidebarSelection)
        .navigationSplitViewColumnWidth(
            min: 168,
            ideal: Theme.sidebarWidth,
            max: 260
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private func sidebarRow(symbol: String, title: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 13))
        } icon: {
            IconWell(symbol: symbol)
        }
        .padding(.vertical, 3)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 6)
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
                PageHeader(symbol: pane.symbolName, title: pane.title, subtitle: pane.summary)
            }
            .navigationTitle(pane.title)
            .toolbar {
                // A settings page has no toolbar controls of its own, but the
                // window still needs a toolbar: without one AppKit centres the
                // window title and drops the titlebar separator, so Settings
                // looked unlike every library page.
                ToolbarItem(placement: .primaryAction) {
                    Color.clear.frame(width: 0, height: 0)
                }
            }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(
                symbol: viewModel.sidebarSelection.symbolName,
                title: viewModel.sidebarSelection.title,
                subtitle: librarySubtitle
            )
        }
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
            ForEach(viewModel.visibleApps) { app in
                AppRowView(viewModel: viewModel, app: app)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    /// Line under the page title. The header already names the filter, so this
    /// says how much is in it rather than repeating the title.
    private var librarySubtitle: String {
        if !viewModel.searchText.isEmpty {
            let count = viewModel.visibleApps.count
            return count == 1 ? "1 result for \"\(viewModel.searchText)\""
                : "\(count) results for \"\(viewModel.searchText)\""
        }
        switch viewModel.sidebarSelection {
        case .all:
            return "Every app installed on this Mac."
        case .protected:
            let count = viewModel.protectedCount
            return count == 1 ? "1 app asks for Touch ID before it opens."
                : "\(count) apps ask for Touch ID before they open."
        case .favorites:
            return "Apps you starred for quick access."
        case .settings, .category:
            return ""
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
        if viewModel.isCatalogueEmpty {
            return "No Applications"
        }
        if !viewModel.searchText.isEmpty {
            return "No Matches"
        }
        switch viewModel.sidebarSelection {
        case .protected: return "Nothing Protected Yet"
        case .favorites: return "No Favorites"
        default: return "No Matches"
        }
    }

    private var emptySymbol: String {
        if viewModel.isCatalogueEmpty {
            return "app.dashed"
        }
        if !viewModel.searchText.isEmpty {
            return "magnifyingglass"
        }
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
        case let .settings(pane): pane.title
        case let .category(category): category.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .protected: "lock.fill"
        case .favorites: "star.fill"
        case let .settings(pane): pane.symbolName
        case let .category(category): category.symbolName
        }
    }

}
