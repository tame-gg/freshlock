//
//  AppEnvironment.swift
//  AppLock
//
//  A tiny dependency-injection container for the GUI process. It builds the
//  core services and, in developer/standalone runs, can host a `LockEngine`
//  directly. In the shipping configuration the *helper* runs the engine; the
//  GUI focuses on configuration. The `runEngineInProcess` flag selects between
//  the two so both work.
//

import AppLockCore
import AppLockEngine
import Foundation

/// Owns the concrete service instances for the running GUI process.
@MainActor
final class AppEnvironment {
    let settingsService: SettingsServiceProtocol
    let authService: AuthenticationServiceProtocol
    let discoveryService: AppDiscoveryServiceProtocol
    let unlockStore: UnlockStateStore
    let accessibility: AccessibilityServiceProtocol
    let helperLoginItem: LoginItemServiceProtocol
    /// The single source of truth for the configuration in this GUI process.
    let configurationStore: ConfigurationStore

    /// Present only when the GUI runs the engine itself (dev / no-helper mode).
    private(set) var engine: LockEngine?

    /// When `true`, the GUI hosts the engine in-process. When `false`, the GUI
    /// assumes the background helper is doing the protecting.
    private let runEngineInProcess: Bool

    private var started = false

    init(
        settingsService: SettingsServiceProtocol = FileSettingsService(),
        authService: AuthenticationServiceProtocol = LocalAuthenticationService(),
        discoveryService: AppDiscoveryServiceProtocol = AppDiscoveryService(),
        unlockStore: UnlockStateStore = UnlockStateStore(),
        accessibility: AccessibilityServiceProtocol = AccessibilityService(),
        helperLoginItem: LoginItemServiceProtocol = LoginItemService(service: .agent(plistName: "gg.tame.applock.helper.plist")),
        runEngineInProcess: Bool = AppEnvironment.helperUnavailable()
    ) {
        self.settingsService = settingsService
        self.authService = authService
        self.discoveryService = discoveryService
        self.unlockStore = unlockStore
        self.accessibility = accessibility
        self.helperLoginItem = helperLoginItem
        self.runEngineInProcess = runEngineInProcess
        self.configurationStore = ConfigurationStore(settingsService: settingsService)
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

    /// Whether the packaged background helper is present. When running from a
    /// bare SwiftPM binary (no `.app`), there is no helper, so the GUI hosts the
    /// engine itself.
    private static func helperUnavailable() -> Bool {
        // The helper lives at Contents/Library/LoginItems/AppLockHelper.app when
        // packaged. Absence means we should run in-process.
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/AppLockHelper.app")
            .checkResourceIsReachableSafely() == false
    }

    static let shared = AppEnvironment()
}

private extension URL {
    /// Non-throwing reachability check.
    func checkResourceIsReachableSafely() -> Bool {
        (try? checkResourceIsReachable()) ?? false
    }
}
