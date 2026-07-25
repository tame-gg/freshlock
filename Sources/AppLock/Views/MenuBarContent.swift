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

        Button("Unlock Until Sleep…") {
            // Unlocking requires authentication; the actual prompt is driven by
            // the lock coordinator when the app is next activated. Here we only
            // surface the standing grant intent for already-running apps.
            for app in viewModel.configuration.enabledProtectedApps {
                unlockStore.grantUnlock(app.bundleIdentifier, scope: .untilSleep)
            }
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
}
