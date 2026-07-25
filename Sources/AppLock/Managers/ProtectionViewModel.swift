//
//  ProtectionViewModel.swift
//  AppLock
//
//  The primary view model backing the main window. It merges the on-disk
//  `Configuration` with freshly-discovered installed apps and exposes the
//  filtered/sorted list the UI renders, plus the mutating actions (toggle
//  protection, favourite, categorise). All persistence flows through here.
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
    @Published private(set) var configuration: Configuration
    @Published var searchText: String = ""
    @Published var sidebarSelection: SidebarItem = .all

    // MARK: Dependencies

    private let settingsService: SettingsServiceProtocol
    private let discoveryService: AppDiscoveryServiceProtocol

    init(
        settingsService: SettingsServiceProtocol,
        discoveryService: AppDiscoveryServiceProtocol
    ) {
        self.settingsService = settingsService
        self.discoveryService = discoveryService
        self.configuration = (try? settingsService.load()) ?? .empty
    }

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

    // MARK: Mutations

    /// Enable/disable protection for an app, creating a config entry on demand.
    func toggleProtection(for app: InstalledApp) {
        mutate(app) { entry in entry.isEnabled.toggle() }
    }

    func toggleFavorite(for app: InstalledApp) {
        mutate(app) { entry in entry.isFavorite.toggle() }
    }

    func setCategory(_ category: AppCategory, for app: InstalledApp) {
        mutate(app) { entry in entry.category = category }
    }

    func setRelockPolicy(_ policy: RelockPolicy?, for app: InstalledApp) {
        mutate(app) { entry in entry.relockPolicy = policy }
    }

    /// Upsert-and-persist helper. Finds (or creates) the config entry for an
    /// app, applies `change`, prunes entries that carry no protection, saves.
    private func mutate(_ app: InstalledApp, _ change: (inout ProtectedApp) -> Void) {
        var entry = configuration.protectedApp(for: app.bundleIdentifier)
            ?? ProtectedApp(from: app)
        change(&entry)

        configuration.protectedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        // Keep the entry only if it still expresses a preference worth storing.
        if entry.isEnabled || entry.isFavorite || entry.category != .other || entry.relockPolicy != nil {
            configuration.protectedApps.append(entry)
        }
        persist()
    }

    private func persist() {
        do {
            try settingsService.save(configuration)
        } catch {
            Log.settings.error("Failed to persist configuration: \(error.localizedDescription)")
        }
    }
}
