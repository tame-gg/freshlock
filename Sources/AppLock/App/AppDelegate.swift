//
//  AppDelegate.swift
//  AppLock
//
//  A minimal `NSApplicationDelegate` used only to bootstrap the background
//  locking engine at launch and to keep AppLock running as an accessory (menu
//  bar) app with no Dock icon.
//

import AppKit
import AppLockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory activation policy = menu-bar utility, no Dock icon. This is
        // the runtime equivalent of `LSUIElement` for an SPM-built binary and
        // is overridden by Info.plist when packaged as a proper .app.
        NSApp.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            AppEnvironment.shared.startServices()
        }
    }
}
