//
//  AppEnvironment.swift
//  AppLock
//
//  A tiny dependency-injection container. Constructing all services in one
//  place keeps `@main` clean and makes it trivial to swap real services for
//  fakes in previews/tests. Everything downstream receives its collaborators
//  through initialisers — no singletons, no service locators (the single
//  `shared` instance exists only because SwiftUI's `App` is created by the
//  runtime before we can inject anything).
//

import AppLockCore
import Foundation

/// Owns the concrete service instances for a running AppLock process, and the
/// managers that compose them into the live locking engine.
@MainActor
final class AppEnvironment {
    // Services
    let settingsService: SettingsServiceProtocol
    let authService: AuthenticationServiceProtocol
    let discoveryService: AppDiscoveryServiceProtocol
    let unlockStore: UnlockStateStore
    let monitor: AppMonitorServiceProtocol
    let overlay: OverlayServiceProtocol
    let accessibility: AccessibilityServiceProtocol
    let loginItem: LoginItemServiceProtocol

    // Managers
    let coordinator: LockCoordinator
    let relockManager: RelockManager

    private var started = false

    init(
        settingsService: SettingsServiceProtocol = FileSettingsService(),
        authService: AuthenticationServiceProtocol = LocalAuthenticationService(),
        discoveryService: AppDiscoveryServiceProtocol = AppDiscoveryService(),
        unlockStore: UnlockStateStore = UnlockStateStore(),
        monitor: AppMonitorServiceProtocol? = nil,
        overlay: OverlayServiceProtocol? = nil,
        accessibility: AccessibilityServiceProtocol? = nil,
        loginItem: LoginItemServiceProtocol? = nil
    ) {
        self.settingsService = settingsService
        self.authService = authService
        self.discoveryService = discoveryService
        self.unlockStore = unlockStore
        let monitor = monitor ?? AppMonitorService()
        let overlay = overlay ?? OverlayService()
        self.monitor = monitor
        self.overlay = overlay
        self.accessibility = accessibility ?? AccessibilityService()
        self.loginItem = loginItem ?? LoginItemService()

        // The coordinator reads the freshest configuration straight from the
        // store on each event; this keeps it decoupled from the view model.
        self.coordinator = LockCoordinator(
            monitor: monitor,
            auth: authService,
            overlay: overlay,
            store: unlockStore,
            configProvider: { (try? settingsService.load()) ?? .empty }
        )
        self.relockManager = RelockManager(store: unlockStore)
    }

    /// Boot the live locking engine. Idempotent.
    func startServices() {
        guard !started else { return }
        started = true
        relockManager.start()
        coordinator.start()
        Log.lifecycle.info("AppLock services started")
    }

    /// The single shared environment for the app process.
    static let shared = AppEnvironment()
}
