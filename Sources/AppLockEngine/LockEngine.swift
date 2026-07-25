//
//  LockEngine.swift
//  AppLockEngine
//
//  The public composition root of the locking engine. It wires together the
//  (internal) monitor, overlay, coordinator and relock manager into a single
//  object that any host process can start — the GUI app *or* the background
//  helper. This is what lets "the helper does the protecting, the GUI only
//  manages configuration" be true: both link `AppLockEngine` and both can spin
//  up a `LockEngine`, but in production only one instance runs the engine.
//

import AppLockCore
import Foundation

/// A ready-to-run locking engine. Construct it with the shared core services
/// and a configuration provider, then call ``start()``.
@MainActor
public final class LockEngine {
    private let monitor: AppMonitorService
    private let overlay: OverlayService
    private let coordinator: LockCoordinator
    private let relockManager: RelockManager

    /// The store other components can observe for live lock state.
    public let unlockStore: UnlockStateStore

    private var started = false

    /// - Parameters:
    ///   - authService: biometric authentication (from `AppLockCore`).
    ///   - unlockStore: the shared unlock-state store.
    ///   - configProvider: returns the freshest `Configuration` on demand. The
    ///     engine reads it on each event so config edits take effect live.
    public init(
        authService: AuthenticationServiceProtocol,
        unlockStore: UnlockStateStore,
        configProvider: @escaping @Sendable () -> Configuration
    ) {
        self.unlockStore = unlockStore
        let monitor = AppMonitorService()
        let overlay = OverlayService()
        self.monitor = monitor
        self.overlay = overlay
        self.coordinator = LockCoordinator(
            monitor: monitor,
            auth: authService,
            overlay: overlay,
            store: unlockStore,
            configProvider: configProvider
        )
        self.relockManager = RelockManager(store: unlockStore)
    }

    /// Boot the live locking engine. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        relockManager.start()
        coordinator.start()
        Log.lifecycle.info("Lock engine started")
    }

    /// Tear down observers and dismiss any overlays.
    public func stop() {
        guard started else { return }
        started = false
        monitor.stop()
        relockManager.stop()
        overlay.dismissAll()
        Log.lifecycle.info("Lock engine stopped")
    }
}
