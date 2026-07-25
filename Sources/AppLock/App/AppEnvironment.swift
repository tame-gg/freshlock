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

import AppKit
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

    /// Whether the GUI should host the locking engine itself.
    ///
    /// The rule is simply: **run in-process unless the background helper is
    /// already running**. This guarantees protection is active out of the box —
    /// including for unsigned local builds where `SMAppService` can't register
    /// the helper — while still deferring to the helper when it *is* live (so we
    /// never run two engines and double-prompt). The helper enabling itself
    /// later takes effect on the next GUI launch.
    private static func helperUnavailable() -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.helperBundleID)
            .isEmpty
    }

    static let helperBundleID = "gg.tame.applock.helper"

    static let shared = AppEnvironment()
}
