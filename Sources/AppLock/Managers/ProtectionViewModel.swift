//
//  ProtectionViewModel.swift
//  AppLock
//
//  The primary view model backing the main window. It merges the shared
//  `ConfigurationStore` with freshly-discovered installed apps and exposes the
//  filtered/sorted list the UI renders, plus the mutating actions (toggle
//  protection, favourite, categorise, relock policy). All persistence flows
//  through the store, so preferences and the list never fight over the document.
//

import AppLockCore
import Combine
import Foundation
import SwiftUI

/// Sidebar selection identifying which slice of apps to show.
enum SidebarItem: Hashable {
    case all
    case protected
    case favorites
    case category(AppCategory)
}

@MainActor
final class ProtectionViewModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var installedApps: [InstalledApp] = []
    @Published var searchText: String = ""
    @Published var sidebarSelection: SidebarItem = .all
    /// Bundle id of the app shown in the detail inspector, if any.
    @Published var selectedAppID: String?

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

    var configuration: Configuration { store.configuration }

    // MARK: Lifecycle

    /// Refresh the installed-app catalogue off the main thread.
    func refreshInstalledApps() async {
        let service = discoveryService
        let apps = await Task.detached { service.discoverApps() }.value
        installedApps = apps
    }

    // MARK: Derived data

    /// The apps to display for the current sidebar selection and search query.
    var visibleApps: [InstalledApp] {
        let base: [InstalledApp]
        switch sidebarSelection {
        case .all:
            base = installedApps
        case .protected:
            base = installedApps.filter { isProtected($0.bundleIdentifier) }
        case .favorites:
            base = installedApps.filter { isFavorite($0.bundleIdentifier) }
        case .category(let category):
            base = installedApps.filter { protectedApp(for: $0.bundleIdentifier)?.category == category }
        }

        let filtered = searchText.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }

        // Favourites float to the top, then alphabetical.
        return filtered.sorted {
            let lf = isFavorite($0.bundleIdentifier)
            let rf = isFavorite($1.bundleIdentifier)
            if lf != rf { return lf }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The installed app currently selected for detailed editing.
    var selectedApp: InstalledApp? {
        guard let id = selectedAppID else { return nil }
        return installedApps.first { $0.bundleIdentifier == id }
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
    var defaultRelockPolicy: RelockPolicy { configuration.settings.defaultRelockPolicy }

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
                || entry.relockPolicy != nil || entry.terminateAfterFailures != nil {
                config.protectedApps.append(entry)
            }
        }
    }
}
