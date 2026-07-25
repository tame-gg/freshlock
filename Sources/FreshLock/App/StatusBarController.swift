//
//  StatusBarController.swift
//  FreshLock
//
//  Manages the menu-bar item using AppKit's `NSStatusItem` rather than SwiftUI's
//  `MenuBarExtra`. Two reasons:
//
//  1. `MenuBarExtra(isInserted:)` sends SwiftUI into an infinite scene-update
//     loop on this macOS whenever another window opens — so hiding the icon that
//     way is not viable.
//  2. An `NSStatusItem` can be added/removed instantly, giving a reliable
//     "Show icon in menu bar" toggle.
//
//  The menu is rebuilt on open, so the protected list, each app's running state
//  and the lock state are current. Protected apps appear as their real Finder
//  icons: the point of opening this menu is to see what FreshLock is guarding
//  right now, and an icon reads faster than a line of text.
//

import AppKit
import Combine
import FreshLockCore
import FreshLockEngine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// Menu-sized app icons keyed by path + running state. Finder icon lookups
    /// are disk-backed, and the menu is rebuilt on every open.
    private var iconCache: [String: NSImage] = [:]

    /// Keeps the menu readable when a lot of apps are protected; the rest are one
    /// click away in the main window.
    private static let maxListedApps = 12

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        // Default the preference to "visible" so a first run shows the icon.
        UserDefaults.standard.register(defaults: [MenuBarPreference.key: true])
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        // The glyph reports whether anything is currently unlocked, so the state
        // is legible without opening the menu.
        environment.unlockStore.$grants
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButtonGlyph() }
            .store(in: &cancellables)
        updateVisibility()
    }

    @objc private func defaultsChanged() {
        updateVisibility()
    }

    private var shouldShow: Bool {
        UserDefaults.standard.bool(forKey: MenuBarPreference.key)
    }

    /// Add or remove the status item to match the preference.
    private func updateVisibility() {
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            // Items are rebuilt on every open with the enablement we want. Left
            // on, AppKit's automatic validation re-enables anything whose target
            // responds to the selector, which kept "Lock All" live with nothing
            // unlocked and un-greyed the summary line.
            menu.autoenablesItems = false
            item.menu = menu
            statusItem = item
            updateButtonGlyph()
        } else if !shouldShow, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Closed shield when everything is locked, open shield while a grant is
    /// live. Template images, so the menu bar tints them itself.
    private func updateButtonGlyph() {
        guard let button = statusItem?.button else { return }
        let anyUnlocked = !environment.unlockStore.unlockedBundleIDs.isEmpty
        let symbol = anyUnlocked ? "lock.open.trianglebadge.exclamationmark" : "lock.shield.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FreshLock")
        image?.isTemplate = true
        button.image = image
        button.toolTip = anyUnlocked ? "FreshLock — some apps are unlocked" : "FreshLock — all apps locked"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let apps = environment.configurationStore.configuration.enabledProtectedApps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let unlockedIDs = environment.unlockStore.unlockedBundleIDs

        menu.addItem(headerItem(protected: apps.count, unlocked: unlockedIDs.count))
        menu.addItem(.separator())

        if apps.isEmpty {
            menu.addItem(disabledItem("Nothing is protected yet"))
            add(menu, "Choose Apps to Protect…", #selector(openMain), symbol: "square.grid.2x2")
        } else {
            for app in apps.prefix(Self.maxListedApps) {
                menu.addItem(appItem(for: app, isUnlocked: unlockedIDs.contains(app.bundleIdentifier)))
            }
            if apps.count > Self.maxListedApps {
                let remaining = apps.count - Self.maxListedApps
                add(menu, "\(remaining) More in FreshLock…", #selector(openMain), symbol: "ellipsis")
            }
        }
        menu.addItem(.separator())

        let lockAll = add(menu, "Lock All", #selector(lockAll), symbol: "lock.fill")
        lockAll.isEnabled = !unlockedIDs.isEmpty
        add(menu, "Unlock Until Sleep", #selector(unlockUntilSleep), symbol: "lock.open.fill")
        add(menu, "Unlock Until Logout", #selector(unlockUntilLogout), symbol: "lock.open.rotation")
        menu.addItem(.separator())

        add(menu, "Open FreshLock…", #selector(openMain), symbol: "macwindow")
        add(menu, "Settings…", #selector(openPreferences), key: ",", symbol: "gearshape")
        add(menu, "About FreshLock", #selector(openAbout), symbol: "info.circle")
        menu.addItem(.separator())
        add(menu, "Quit FreshLock", #selector(quit), key: "q", symbol: "power")
    }

    /// Summary line: how much is protected, and how much of it is open right now.
    private func headerItem(protected: Int, unlocked: Int) -> NSMenuItem {
        let summary = if protected == 0 {
            "FreshLock"
        } else if unlocked == 0 {
            "\(protected) app\(protected == 1 ? "" : "s") protected"
        } else {
            "\(protected) app\(protected == 1 ? "" : "s") protected · \(unlocked) unlocked"
        }
        return disabledItem(summary)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    /// A protected app: its real icon, dimmed while the app is not running, with
    /// an open-lock marker only when a grant is live. Locked is the resting
    /// state, so it carries no marker of its own.
    private func appItem(for app: ProtectedApp, isUnlocked: Bool) -> NSMenuItem {
        let isRunning = Self.newestRunningInstance(of: app.bundleIdentifier) != nil
        let item = NSMenuItem(title: app.name, action: #selector(protectedAppAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.bundleIdentifier
        item.image = icon(for: app, isRunning: isRunning)
        item.state = isUnlocked ? .on : .off
        item.onStateImage = Self.symbolImage("lock.open.fill")
        item.offStateImage = nil
        item.toolTip = isUnlocked
            ? "Lock \(app.name) now"
            : (isRunning ? "Bring \(app.name) to the front" : "Open \(app.name)")
        return item
    }

    @discardableResult
    private func add(
        _ menu: NSMenu,
        _ title: String,
        _ action: Selector,
        key: String = "",
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = Self.symbolImage(symbol)
        }
        menu.addItem(item)
        return item
    }

    // MARK: - Images

    /// Finder icon at menu size. Apps that are not running are drawn faded, so
    /// the list separates "guarded and live" from "guarded and idle" at a glance.
    private func icon(for app: ProtectedApp, isRunning: Bool) -> NSImage? {
        let key = "\(app.path)|\(isRunning)"
        if let cached = iconCache[key] {
            return cached
        }
        guard FileManager.default.fileExists(atPath: app.path) else {
            return Self.symbolImage("app.dashed")
        }
        let source = NSWorkspace.shared.icon(forFile: app.path)
        let side = Theme.menuAppIconSize
        let scaled = NSImage(size: NSSize(width: side, height: side))
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: isRunning ? 1.0 : 0.45
        )
        scaled.unlockFocus()
        iconCache[key] = scaled
        return scaled
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: Theme.menuSymbolSize, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    // MARK: - Actions

    /// Clicking a protected app locks it when it holds a live unlock, and opens
    /// it otherwise. Locking here only revokes the grant; the engine's own
    /// liveness pass puts the overlay back if that app is in front.
    @objc private func protectedAppAction(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if environment.unlockStore.unlockedBundleIDs.contains(bundleID) {
            environment.unlockStore.lock(bundleID)
            return
        }
        if let running = Self.newestRunningInstance(of: bundleID) {
            running.activate()
            return
        }
        guard
            let app = environment.configurationStore.configuration.protectedApp(for: bundleID),
            FileManager.default.fileExists(atPath: app.path)
        else { return }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: app.path),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func lockAll() {
        if let engine = environment.engine {
            engine.lockAllNow()
        } else {
            environment.unlockStore.lockAll()
        }
    }

    /// Requires LocalAuthentication - same posture as Unlock All / overlay unlock.
    @objc private func unlockUntilSleep() {
        if let engine = environment.engine {
            engine.unlockUntilSleepNow()
            return
        }
        // No in-process engine (unusual): still gate on LA before granting.
        authenticateThenGrant(.untilSleep)
    }

    @objc private func unlockUntilLogout() {
        if let engine = environment.engine {
            engine.unlockUntilLogoutNow()
            return
        }
        authenticateThenGrant(.untilLogout)
    }

    private func authenticateThenGrant(_ scope: UnlockScope) {
        Task { @MainActor in
            let result = await environment.authService.authenticate(
                reason: scope == .untilLogout
                    ? "unlock protected apps until logout"
                    : "unlock protected apps until sleep"
            )
            guard case .success = result else { return }
            for app in environment.configurationStore.configuration.enabledProtectedApps {
                // Only grant for processes that are actually running - a PID-less
                // unlock would survive quit/relaunch and break the lock model.
                // Prefer frontmost / newest instance (never `.first`).
                guard let pid = Self.newestRunningInstance(of: app.bundleIdentifier)?.processIdentifier
                else { continue }
                environment.unlockStore.grantUnlock(app.bundleIdentifier, scope: scope, sessionPID: pid)
            }
        }
    }

    /// Newest live instance for a bundle id, or `nil` when it is not running.
    private static func newestRunningInstance(of bundleID: String) -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
            .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
    }

    @objc private func openMain() {
        WindowManager.shared.showMain()
    }

    @objc private func openPreferences() {
        WindowManager.shared.showPreferences()
    }

    @objc private func openAbout() {
        WindowManager.shared.showAbout()
    }

    /// Routes through `NSApp.terminate`, which hits AppDelegate's
    /// `applicationShouldTerminate` LocalAuthentication gate.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
