//
//  MainView.swift
//  AppLock
//
//  The main window: a `NavigationSplitView` with a source-list sidebar and a
//  searchable app list, mirroring the layout of Apple's own utilities.
//

import AppLockCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: ProtectionViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            appList
        } detail: {
            detailPane
        }
        .task {
            await viewModel.refreshInstalledApps()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section {
                label("All Apps", systemImage: "square.grid.2x2.fill", tint: .gray, tag: .all)
                label("Protected", systemImage: "lock.fill", tint: .blue, tag: .protected)
                    .badge(viewModel.protectedCount)
                label("Favourites", systemImage: "star.fill", tint: .yellow, tag: .favorites)
                    .badge(viewModel.favoritesCount)
            }
            Section("Categories") {
                ForEach(AppCategory.allCases, id: \.self) { category in
                    label(category.displayName, systemImage: category.symbolName, tint: .accentColor, tag: .category(category))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        .navigationTitle("AppLock")
    }

    private func label(_ title: String, systemImage: String, tint: Color, tag: SidebarItem) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .tag(tag)
    }

    // MARK: App list (content column)

    private var appList: some View {
        Group {
            if viewModel.visibleApps.isEmpty {
                ContentUnavailableView(
                    "No Apps",
                    systemImage: "magnifyingglass",
                    description: Text("No applications match your selection.")
                )
            } else {
                List(selection: $viewModel.selectedAppID) {
                    if !viewModel.favoriteVisibleApps.isEmpty {
                        Section("Favourites") {
                            ForEach(viewModel.favoriteVisibleApps) { row(for: $0) }
                        }
                        Section("All Apps") {
                            ForEach(viewModel.nonFavoriteVisibleApps) { row(for: $0) }
                        }
                    } else {
                        ForEach(viewModel.visibleApps) { row(for: $0) }
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search apps")
        .navigationTitle("Apps")
    }

    private func row(for app: InstalledApp) -> some View {
        AppRowView(
            app: app,
            isProtected: viewModel.isProtected(app.bundleIdentifier),
            isFavorite: viewModel.isFavorite(app.bundleIdentifier),
            onToggleProtection: { viewModel.toggleProtection(for: app) },
            onToggleFavorite: { viewModel.toggleFavorite(for: app) }
        )
        .tag(app.bundleIdentifier)
    }

    // MARK: Detail (inspector column)

    @ViewBuilder private var detailPane: some View {
        if let app = viewModel.selectedApp {
            AppDetailView(viewModel: viewModel, app: app)
        } else {
            ContentUnavailableView(
                "Select an App",
                systemImage: "lock.square.dashed",
                description: Text("Choose an app to configure its protection and auto-relock.")
            )
        }
    }
}
