//
//  MainView.swift
//  FreshLock
//
//  The main window, redesigned in the koels.net spirit: a single, dark,
//  uncluttered screen — a bold gradient wordmark, a prominent search, a simple
//  three-way filter, and a clean card list of apps with one-tap protection.
//  Per-app options live in a popover so the list itself stays calm.
//

import FreshLockCore
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: ProtectionViewModel

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                Divider().overlay(Theme.stroke)
                list
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .preferredColorScheme(.dark)
        .task { await viewModel.refreshInstalledApps() }
        .onAppear {
            Task { await viewModel.refreshInstalledApps() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("App Protection")
                    HStack(spacing: 0) {
                        Text("Fresh").foregroundStyle(Theme.textPrimary)
                        Text("Lock").foregroundStyle(Theme.brandGradient)
                    }
                    .font(.system(size: 40, weight: .heavy)).tracking(-0.5)
                }
                Spacer()
                protectedPill
                Button {
                    WindowManager.shared.showPreferences()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().stroke(Theme.stroke))
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }

            searchField
            FilterBar(selection: $viewModel.sidebarSelection,
                      protectedCount: viewModel.protectedCount,
                      favoritesCount: viewModel.favoritesCount)
        }
    }

    private var protectedPill: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.green).frame(width: 7, height: 7)
            Text("\(viewModel.protectedCount) protected")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().stroke(Theme.stroke))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
            TextField("Search apps", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .font(.system(size: 14))
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.baseElevated, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
    }

    // MARK: List

    private var list: some View {
        Group {
            if viewModel.isLoadingCatalogue && viewModel.installedApps.isEmpty {
                ProgressView("Scanning applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.visibleApps) { app in
                            AppRowView(viewModel: viewModel, app: app)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.isCatalogueEmpty ? "app.dashed" : "magnifyingglass")
                .font(.system(size: 34)).foregroundStyle(Theme.textMuted)
            if viewModel.isCatalogueEmpty {
                Text("No applications found").font(.headline).foregroundStyle(Theme.textSecondary)
                Text(viewModel.catalogueError ?? "Check /Applications and try again.")
                    .font(.subheadline).foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Scan Again") {
                    Task { await viewModel.refreshInstalledApps() }
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.isFilterEmpty {
                Text("No apps match").font(.headline).foregroundStyle(Theme.textSecondary)
                Text("Try clearing search or switching to All Apps.")
                    .font(.subheadline).foregroundStyle(Theme.textMuted)
                Button("Show All Apps") {
                    viewModel.searchText = ""
                    viewModel.sidebarSelection = .all
                }
                .buttonStyle(.bordered)
            } else {
                Text("No apps match").font(.headline).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The three-way koels-style pill filter.
private struct FilterBar: View {
    @Binding var selection: SidebarItem
    let protectedCount: Int
    let favoritesCount: Int

    var body: some View {
        HStack(spacing: 8) {
            pill("All Apps", tag: .all, count: nil)
            pill("Protected", tag: .protected, count: protectedCount)
            pill("Favourites", tag: .favorites, count: favoritesCount)
            Spacer()
        }
    }

    private func pill(_ title: String, tag: SidebarItem, count: Int?) -> some View {
        let active = selection == tag
        return Button {
            selection = tag
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(active ? Theme.base : Theme.textMuted)
                }
            }
            .foregroundStyle(active ? Theme.base : Theme.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background {
                if active {
                    Capsule().fill(Theme.brandGradient)
                } else {
                    Capsule().fill(Theme.card).overlay(Capsule().stroke(Theme.stroke))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
