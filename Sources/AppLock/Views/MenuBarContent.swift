//
//  MenuBarContent.swift
//  AppLock
//
//  The menu-bar dropdown. Kept intentionally lean — the menu bar is for quick
//  actions (lock/unlock, open preferences), while configuration lives in the
//  main window.
//

import AppKit
import AppLockCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var viewModel: ProtectionViewModel
    @ObservedObject var unlockStore: UnlockStateStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let protectedCount = viewModel.configuration.enabledProtectedApps.count

        Text("AppLock — \(protectedCount) protected")
            .font(.headline)

        Divider()

        Button("Lock All") {
            unlockStore.lockAll()
        }
        .disabled(unlockStore.grants.isEmpty)

        Button("Unlock Until Sleep") {
            grantAll(.untilSleep)
        }

        Button("Unlock Until Logout") {
            grantAll(.untilLogout)
        }

        Divider()

        Button("Open Preferences…") {
            openWindow(id: AppWindowID.main)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About AppLock") {
            openWindow(id: AppWindowID.about)
        }

        Divider()

        Button("Quit AppLock") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// Grant a temporary unlock to every enabled protected app. Note: these
    /// grants apply to apps already unlocked/running; a *locked* app will still
    /// require authentication when next activated, because unlocking must be
    /// user-authenticated — the menu can only extend, not bypass, protection.
    private func grantAll(_ scope: UnlockScope) {
        for app in viewModel.configuration.enabledProtectedApps {
            unlockStore.grantUnlock(app.bundleIdentifier, scope: scope)
        }
    }
}
