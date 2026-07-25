//
//  ProtectionViewModel.swift
//  FreshLock
//
//  The primary view model backing the main window. It merges the shared
//  `ConfigurationStore` with freshly-discovered installed apps and exposes the
//  filtered/sorted list the UI renders, plus the mutating actions (toggle
//  protection, favourite, categorise, relock policy). All persistence flows
//  through the store, so preferences and the list never fight over the document.
//

import Combine
import Foundation
import FreshLockCore
import SwiftUI

/// Sidebar selection identifying which slice of apps to show, or which
/// Settings page to open in the detail pane.
enum SidebarItem: Hashable {
    case all
    case protected
    case favorites
    case settings(SettingsPane)
    case category(AppCategory)

    /// The settings page this selection shows, or `nil` for a library filter.
    var settingsPane: SettingsPane? {
        if case let .settings(pane) = self {
            return pane
        }
        return nil
    }
}

@MainActor
final class ProtectionViewModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var isLoadingCatalogue = false
    @Published private(set) var catalogueError: String?
    @Published var searchText: String = ""
    @Published var sidebarSelection: SidebarItem = .all
    /// Bundle id of the app shown in the detail inspector, if any.
    @Published var selectedAppID: String?
    /// Bundle id whose per-app options popover is open, if any.
    @Published var optionsPresentedFor: String?

    // MARK: Dependencies

    let store: ConfigurationStore
    private let discoveryService: AppDiscoveryServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    init(store: ConfigurationStore, discoveryService: AppDiscoveryServiceProtocol) {
        self.store = store
        self.discoveryService = discoveryService
        // Re-render whenever the shared configuration changes underneath us
        // (e.g. an import performed from Preferences).
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var configuration: Configuration {
        store.configuration
    }

    // MARK: Lifecycle

    /// Refresh the installed-app catalogue off the main thread.
    func refreshInstalledApps() async {
        isLoadingCatalogue = true
        catalogueError = nil
        let service = discoveryService
        let apps = await Task.detached { service.discoverApps() }.value
        installedApps = apps
        isLoadingCatalogue = false
        if apps.isEmpty {
            catalogueError = "No applications found in Applications folders."
        }
    }

    /// True when the catalogue itself is empty (not merely filtered).
    var isCatalogueEmpty: Bool {
        installedApps.isEmpty && !isLoadingCatalogue
    }

    /// True when filters/search hide everything but apps were discovered.
    var isFilterEmpty: Bool {
        !installedApps.isEmpty && visibleApps.isEmpty
    }

    // MARK: Derived data

    /// The apps to display for the current sidebar selection and search query.
    var visibleApps: [InstalledApp] {
        let base: [InstalledApp] = switch sidebarSelection {
        case .all:
            installedApps
        case .protected:
            installedApps.filter { isProtected($0.bundleIdentifier) }
        case .favorites:
            installedApps.filter { isFavorite($0.bundleIdentifier) }
        case .settings:
            []
        case let .category(category):
            installedApps.filter { protectedApp(for: $0.bundleIdentifier)?.category == category }
        }

        let filtered = searchText.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }

        // Favorites float to the top, then alphabetical.
        return filtered.sorted {
            let lf = isFavorite($0.bundleIdentifier)
            let rf = isFavorite($1.bundleIdentifier)
            if lf != rf {
                return lf
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The installed app currently selected for detailed editing.
    var selectedApp: InstalledApp? {
        guard let id = selectedAppID else { return nil }
        return installedApps.first { $0.bundleIdentifier == id }
    }

    /// Number of apps with protection enabled (for the sidebar badge).
    var protectedCount: Int {
        configuration.enabledProtectedApps.count
    }

    /// Number of favourited apps (for the sidebar badge).
    var favoritesCount: Int {
        configuration.protectedApps.filter(\.isFavorite).count
    }

    /// Visible apps split into favorites and the rest, for sectioned display.
    var favoriteVisibleApps: [InstalledApp] {
        visibleApps.filter { isFavorite($0.bundleIdentifier) }
    }

    var nonFavoriteVisibleApps: [InstalledApp] {
        visibleApps.filter { !isFavorite($0.bundleIdentifier) }
    }

    // MARK: Lookups

    func protectedApp(for bundleID: String) -> ProtectedApp? {
        configuration.protectedApp(for: bundleID)
    }

    func isProtected(_ bundleID: String) -> Bool {
        protectedApp(for: bundleID)?.isEnabled ?? false
    }

    func isFavorite(_ bundleID: String) -> Bool {
        protectedApp(for: bundleID)?.isFavorite ?? false
    }

    /// The global default, surfaced so the editor can label the "Default" option.
    var defaultRelockPolicy: RelockPolicy {
        configuration.settings.defaultRelockPolicy
    }

    // MARK: Mutations

    func toggleProtection(for app: InstalledApp) {
        mutate(app) { $0.isEnabled.toggle() }
    }

    func toggleFavorite(for app: InstalledApp) {
        mutate(app) { $0.isFavorite.toggle() }
    }

    func setCategory(_ category: AppCategory, for app: InstalledApp) {
        mutate(app) { $0.category = category }
    }

    func setRelockPolicy(_ policy: RelockPolicy?, for app: InstalledApp) {
        mutate(app) { $0.relockPolicy = policy }
    }

    func setTerminateAfterFailures(_ limit: Int?, for app: InstalledApp) {
        mutate(app) { $0.terminateAfterFailures = limit }
    }

    /// Upsert-and-persist helper. Finds (or creates) the config entry for an
    /// app, applies `change`, prunes entries that carry no preference, saves.
    private func mutate(_ app: InstalledApp, _ change: (inout ProtectedApp) -> Void) {
        store.update { config in
            var entry = config.protectedApp(for: app.bundleIdentifier) ?? ProtectedApp(from: app)
            change(&entry)
            config.protectedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
            if entry.isEnabled || entry.isFavorite || entry.category != .other
                || entry.relockPolicy != nil || entry.terminateAfterFailures != nil
            {
                config.protectedApps.append(entry)
            }
        }
    }
}
