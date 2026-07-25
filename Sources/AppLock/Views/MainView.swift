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
        } detail: {
            detail
        }
        .task {
            await viewModel.refreshInstalledApps()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
            Section {
                label("All Apps", systemImage: "square.grid.2x2", tag: .all)
                label("Protected", systemImage: "lock.fill", tag: .protected)
                label("Favourites", systemImage: "star.fill", tag: .favorites)
            }
            Section("Categories") {
                ForEach(AppCategory.allCases, id: \.self) { category in
                    label(category.displayName, systemImage: category.symbolName, tag: .category(category))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .navigationTitle("AppLock")
    }

    private func label(_ title: String, systemImage: String, tag: SidebarItem) -> some View {
        Label(title, systemImage: systemImage).tag(tag)
    }

    // MARK: Detail

    private var detail: some View {
        Group {
            if viewModel.visibleApps.isEmpty {
                ContentUnavailableView(
                    "No Apps",
                    systemImage: "magnifyingglass",
                    description: Text("No applications match your selection.")
                )
            } else {
                List {
                    ForEach(viewModel.visibleApps) { app in
                        AppRowView(
                            app: app,
                            isProtected: viewModel.isProtected(app.bundleIdentifier),
                            isFavorite: viewModel.isFavorite(app.bundleIdentifier),
                            onToggleProtection: { viewModel.toggleProtection(for: app) },
                            onToggleFavorite: { viewModel.toggleFavorite(for: app) }
                        )
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search apps")
    }
}
