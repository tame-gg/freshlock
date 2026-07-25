//
//  WindowManager.swift
//  FreshLock
//
//  Hosts the main and About windows as AppKit `NSWindow`s (via
//  `NSHostingController`) rather than SwiftUI `Window` scenes. This gives the
//  AppDelegate full control over *when* they appear: the main window is never
//  shown automatically at launch — only when the user asks (reopening FreshLock,
//  the menu-bar "Open FreshLock" item, or finishing onboarding). A SwiftUI
//  `Window` scene, by contrast, opens itself at launch and can't be reopened
//  from AppKit once suppressed.
//
//  Preferences remains a SwiftUI `Settings` scene, opened via the standard
//  `showSettingsWindow:` action.
//

import AppKit
import FreshLockCore
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private let environment = AppEnvironment.shared
    private var mainController: NSWindowController?
    private var aboutController: NSWindowController?
    private var prefsController: NSWindowController?
    private var settingsViewModel: SettingsViewModel?

    /// Show (creating if needed) the main window and bring it to the front.
    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let controller = mainController {
            controller.window?.makeKeyAndOrderFront(nil)
            Task { await environment.protectionViewModel.refreshInstalledApps() }
            return
        }
        let hosting = NSHostingController(rootView: MainView(viewModel: environment.protectionViewModel))
        let window = Self.makeWindow(
            title: "FreshLock",
            contentViewController: hosting,
            size: NSSize(width: 680, height: 680),
            minSize: NSSize(width: 560, height: 520)
        )
        window.setFrameAutosaveName("FreshLockMainWindow")
        mainController = NSWindowController(window: window)
        mainController?.showWindow(nil)
        Task { await environment.protectionViewModel.refreshInstalledApps() }
    }

    /// Show the About window.
    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        if let controller = aboutController {
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let fitting = hosting.sizeThatFits(in: NSSize(width: 400, height: 10_000))
        let contentSize = NSSize(
            width: max(360, min(460, ceil(fitting.width))),
            height: max(280, ceil(fitting.height))
        )
        let window = Self.makeWindow(
            title: "About FreshLock",
            contentViewController: hosting,
            size: contentSize,
            minSize: NSSize(width: 360, height: 280),
            resizable: false
        )
        aboutController = NSWindowController(window: window)
        aboutController?.showWindow(nil)
    }

    /// Open Preferences. Hosted in AppKit because the SwiftUI `Settings` scene
    /// can't be opened reliably from code on this macOS (`showSettingsWindow:`
    /// is a no-op here).
    func showPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if let controller = prefsController {
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let viewModel = settingsViewModel ?? SettingsViewModel(
            store: environment.configurationStore,
            loginItem: environment.helperLoginItem
        )
        settingsViewModel = viewModel
        let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
        let window = Self.makeWindow(
            title: "Preferences",
            contentViewController: hosting,
            size: NSSize(width: 500, height: 640),
            minSize: NSSize(width: 500, height: 480)
        )
        prefsController = NSWindowController(window: window)
        prefsController?.showWindow(nil)
    }

    // MARK: - Window construction

    private static func makeWindow(
        title: String,
        contentViewController: NSViewController,
        size: NSSize,
        minSize: NSSize,
        resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable {
            style.insert(.resizable)
        }
        let window = NSWindow(contentViewController: contentViewController)
        window.styleMask = style
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(size)
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
