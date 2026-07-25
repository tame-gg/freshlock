//
//  AppEnvironment.swift
//  FreshLock
//
//  A tiny dependency-injection container for the GUI process. It builds the
//  core services and, in developer/standalone runs, can host a `LockEngine`
//  directly. In the shipping configuration the *helper* runs the engine; the
//  GUI focuses on configuration. The `runEngineInProcess` flag selects between
//  the two so both work.
//

import AppKit
import FreshLockCore
import FreshLockEngine
import Foundation

/// Owns the concrete service instances for the running GUI process.
@MainActor
final class AppEnvironment {
    let settingsService: SettingsServiceProtocol
    let authService: AuthenticationServiceProtocol
    let discoveryService: AppDiscoveryServiceProtocol
    let unlockStore: UnlockStateStore
    let helperLoginItem: LoginItemServiceProtocol
    /// The single source of truth for the configuration in this GUI process.
    let configurationStore: ConfigurationStore
    /// The view model backing the main window (owned here so the AppKit-hosted
    /// window and any SwiftUI scene share one instance).
    let protectionViewModel: ProtectionViewModel

    /// Present only when the GUI runs the engine itself (dev / no-helper mode).
    private(set) var engine: LockEngine?

    /// When `true`, the GUI hosts the engine in-process. The GUI is authoritative
    /// whenever it is running: it always runs the engine, and the background
    /// helper stands down while the GUI is alive (see `FreshLockHelper/main.swift`).
    /// This makes protection reliable out of the box — including unsigned builds
    /// where the helper can't be registered — and guarantees the two never run
    /// two engines at once.
    private let runEngineInProcess: Bool

    private var started = false

    init(
        settingsService: SettingsServiceProtocol = FileSettingsService(),
        authService: AuthenticationServiceProtocol = LocalAuthenticationService(),
        discoveryService: AppDiscoveryServiceProtocol = AppDiscoveryService(),
        unlockStore: UnlockStateStore = UnlockStateStore(),
        helperLoginItem: LoginItemServiceProtocol = LoginItemService(service: .agent(plistName: "gg.tame.freshlock.helper.plist")),
        runEngineInProcess: Bool = true
    ) {
        self.settingsService = settingsService
        self.authService = authService
        self.discoveryService = discoveryService
        self.unlockStore = unlockStore
        self.helperLoginItem = helperLoginItem
        self.runEngineInProcess = runEngineInProcess
        let store = ConfigurationStore(settingsService: settingsService)
        self.configurationStore = store
        self.protectionViewModel = ProtectionViewModel(store: store, discoveryService: discoveryService)
    }

    /// Boot whatever this process is responsible for.
    func startServices() {
        guard !started else { return }
        started = true

        if runEngineInProcess {
            let engine = LockEngine(
                authService: authService,
                unlockStore: unlockStore,
                configProvider: { [settingsService] in (try? settingsService.load()) ?? .empty },
                configFileURL: settingsService.storeURL
            )
            engine.start()
            self.engine = engine
            Log.lifecycle.info("GUI is hosting the lock engine in-process")
        } else {
            Log.lifecycle.info("Delegating protection to the background helper")
        }
    }

    static let helperBundleID = "gg.tame.freshlock.helper"

    static let shared = AppEnvironment()
}
