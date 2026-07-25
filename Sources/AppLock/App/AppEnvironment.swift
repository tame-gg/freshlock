//
//  AppEnvironment.swift
//  AppLock
//
//  A tiny dependency-injection container. Constructing all services in one
//  place keeps `@main` clean and makes it trivial to swap real services for
//  fakes in previews/tests. Everything downstream receives its collaborators
//  through initialisers — no singletons, no service locators.
//

import AppLockCore
import Foundation

/// Owns the concrete service instances for a running AppLock process.
@MainActor
final class AppEnvironment {
    let settingsService: SettingsServiceProtocol
    let authService: AuthenticationServiceProtocol
    let discoveryService: AppDiscoveryServiceProtocol
    let unlockStore: UnlockStateStore

    init(
        settingsService: SettingsServiceProtocol = FileSettingsService(),
        authService: AuthenticationServiceProtocol = LocalAuthenticationService(),
        discoveryService: AppDiscoveryServiceProtocol = AppDiscoveryService(),
        unlockStore: UnlockStateStore = UnlockStateStore()
    ) {
        self.settingsService = settingsService
        self.authService = authService
        self.discoveryService = discoveryService
        self.unlockStore = unlockStore
    }

    /// The single shared environment for the app process. This is the *only*
    /// global in the codebase, and it exists solely because SwiftUI's `App`
    /// type is created by the runtime before we can inject anything.
    static let shared = AppEnvironment()
}
