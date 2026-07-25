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
//  The menu is rebuilt on open so the protected count and lock state are current.
//

import AppKit
import FreshLockCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        // Default the preference to "visible" so a first run shows the icon.
        UserDefaults.standard.register(defaults: [MenuBarPreference.key: true])
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        updateVisibility()
    }

    @objc private func defaultsChanged() { updateVisibility() }

    private var shouldShow: Bool {
        UserDefaults.standard.bool(forKey: MenuBarPreference.key)
    }

    /// Add or remove the status item to match the preference.
    private func updateVisibility() {
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "FreshLock")
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !shouldShow, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let count = environment.configurationStore.configuration.enabledProtectedApps.count

        let header = NSMenuItem(title: "\(count) app\(count == 1 ? "" : "s") protected", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let lockAll = add(menu, "Lock All", #selector(lockAll))
        lockAll.isEnabled = !environment.unlockStore.grants.isEmpty
        add(menu, "Unlock Until Sleep", #selector(unlockUntilSleep))
        add(menu, "Unlock Until Logout", #selector(unlockUntilLogout))
        menu.addItem(.separator())

        add(menu, "Open FreshLock…", #selector(openMain))
        add(menu, "Preferences…", #selector(openPreferences), key: ",")
        add(menu, "About FreshLock", #selector(openAbout))
        menu.addItem(.separator())
        add(menu, "Quit FreshLock", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func lockAll() { environment.unlockStore.lockAll() }

    @objc private func unlockUntilSleep() { grantAll(.untilSleep) }
    @objc private func unlockUntilLogout() { grantAll(.untilLogout) }

    private func grantAll(_ scope: UnlockScope) {
        for app in environment.configurationStore.configuration.enabledProtectedApps {
            // Only grant for processes that are actually running — a PID-less
            // unlock would survive quit/relaunch and break the lock model.
            // Prefer frontmost / newest instance (never `.first`).
            guard let pid = NSRunningApplication
                .runningApplications(withBundleIdentifier: app.bundleIdentifier)
                .filter({ !$0.isTerminated })
                .sorted(by: { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) })
                .first?
                .processIdentifier
            else { continue }
            environment.unlockStore.grantUnlock(app.bundleIdentifier, scope: scope, sessionPID: pid)
        }
    }

    @objc private func openMain() { WindowManager.shared.showMain() }
    @objc private func openPreferences() { WindowManager.shared.showPreferences() }
    @objc private func openAbout() { WindowManager.shared.showAbout() }
    @objc private func quit() { NSApp.terminate(nil) }
}
