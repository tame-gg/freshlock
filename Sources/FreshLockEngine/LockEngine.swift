//
//  LockEngine.swift
//  FreshLockEngine
//
//  The public composition root of the locking engine. It wires together the
//  (internal) monitor, overlay, coordinator and relock manager into a single
//  object that any host process can start — the GUI app *or* the background
//  helper. This is what lets "the helper does the protecting, the GUI only
//  manages configuration" be true: both link `FreshLockEngine` and both can spin
//  up a `LockEngine`, but in production only one instance runs the engine.
//

import Foundation
import FreshLockCore
import FreshLockEnforce

/// A ready-to-run locking engine. Construct it with the shared core services
/// and a configuration provider, then call ``start()``.
@MainActor
public final class LockEngine {
    private let monitor: AppMonitorService
    private let overlay: OverlayService
    private let accessibility: AccessibilityService
    private let coordinator: LockCoordinator
    private let relockManager: RelockManager
    private let hotKeys: GlobalHotKeyService
    private let enforceSync: EnforcePolicySync
    private let configProvider: @Sendable () -> Configuration
    private var watcher: ConfigurationFileWatcher?
    /// Ids of the currently-registered global shortcuts, for re-registration.
    private var registeredHotKeyIDs: [UInt32] = []

    /// The store other components can observe for live lock state.
    public let unlockStore: UnlockStateStore

    private var started = false

    /// - Parameters:
    ///   - authService: biometric authentication (from `FreshLockCore`).
    ///   - unlockStore: the shared unlock-state store.
    ///   - configProvider: returns the freshest `Configuration` on demand. The
    ///     engine reads it on each event so config edits take effect live.
    ///   - configFileURL: the on-disk configuration path to watch for changes
    ///     (so shortcuts re-register when edited in another process). Pass `nil`
    ///     to disable live reloading.
    public init(
        authService: AuthenticationServiceProtocol,
        unlockStore: UnlockStateStore,
        configProvider: @escaping @Sendable () -> Configuration,
        configFileURL: URL? = nil
    ) {
        self.unlockStore = unlockStore
        self.configProvider = configProvider
        let monitor = AppMonitorService()
        let accessibility = AccessibilityService()
        let overlay = OverlayService(accessibility: accessibility)
        self.monitor = monitor
        self.accessibility = accessibility
        self.overlay = overlay
        hotKeys = GlobalHotKeyService()
        coordinator = LockCoordinator(
            monitor: monitor,
            auth: authService,
            overlay: overlay,
            accessibility: accessibility,
            store: unlockStore,
            configProvider: configProvider
        )
        relockManager = RelockManager(store: unlockStore)
        enforceSync = EnforcePolicySync(
            unlockStore: unlockStore,
            configProvider: configProvider
        )
        if let configFileURL {
            watcher = ConfigurationFileWatcher(url: configFileURL) { [weak self] in
                self?.reloadShortcuts()
                self?.enforceSync.publish()
            }
        }
    }

    /// Boot the live locking engine. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        relockManager.start()
        coordinator.start()
        enforceSync.start()
        reloadShortcuts()
        watcher?.start()
        Log.lifecycle.info("Lock engine started")
    }

    /// Tear down observers and dismiss any overlays.
    public func stop() {
        guard started else { return }
        started = false
        monitor.stop()
        coordinator.stop()
        relockManager.stop()
        watcher?.stop()
        hotKeys.unregisterAll()
        registeredHotKeyIDs.removeAll()
        overlay.dismissAll()
        accessibility.stopWatchingAll()
        Log.lifecycle.info("Lock engine stopped")
    }

    /// (Re)register the global shortcuts from the current settings. Safe to call
    /// repeatedly — it clears and rebuilds the registration set.
    public func reloadShortcuts() {
        hotKeys.unregisterAll()
        registeredHotKeyIDs.removeAll()

        let settings = configProvider().settings
        if let lockAll = settings.lockAllShortcut,
           let id = hotKeys.register(lockAll, handler: { [weak self] in self?.coordinator.lockAllNow() })
        {
            registeredHotKeyIDs.append(id)
        }
        if let unlockAll = settings.unlockAllShortcut,
           let id = hotKeys.register(unlockAll, handler: { [weak self] in self?.coordinator.unlockAllNow() })
        {
            registeredHotKeyIDs.append(id)
        }
    }

    // MARK: - Menu / shortcut entry points (always auth-gated where unlocking)

    public func lockAllNow() {
        coordinator.lockAllNow()
    }

    public func unlockAllNow() {
        coordinator.unlockAllNow()
    }

    public func unlockUntilSleepNow() {
        coordinator.unlockUntilSleepNow()
    }

    public func unlockUntilLogoutNow() {
        coordinator.unlockUntilLogoutNow()
    }
}
