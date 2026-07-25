//
//  AppVisibilityKeeper.swift
//  FreshLockEngine
//
//  Keeps protected apps out of the hidden state while FreshLock holds them
//  locked. A hidden app has no windows to cover, so hiding one is a way to slip
//  past the overlay entirely.
//
//  The hide notification does the real work the instant an app hides; the slow
//  timer only covers paths that never post one. This replaced a 20 Hz per-app
//  poll that ran for as long as an overlay was up.
//

import AppKit

@MainActor
final class AppVisibilityKeeper {
    private static let backstopInterval: TimeInterval = 1.0

    private var keptBundleIDs: Set<String> = []
    private var backstopTimer: Timer?
    private var hideObserver: NSObjectProtocol?

    /// Resolves a bundle id to its live process. Injected so the coordinator's
    /// notion of "the running instance" stays the single source of truth.
    private let runningApp: (String) -> NSRunningApplication?

    init(runningApp: @escaping (String) -> NSRunningApplication?) {
        self.runningApp = runningApp
    }

    func startKeeping(_ bundleID: String) {
        keptBundleIDs.insert(bundleID)
        installHideObserverIfNeeded()
        startBackstopIfNeeded()
        unhide(bundleID)
    }

    func stopKeeping(_ bundleID: String) {
        keptBundleIDs.remove(bundleID)
        guard keptBundleIDs.isEmpty else { return }
        teardown()
    }

    func stopAll() {
        keptBundleIDs.removeAll()
        teardown()
    }

    /// Unhide now, without enrolling the app in ongoing keeping.
    func unhide(_ bundleID: String) {
        guard let running = runningApp(bundleID), running.isHidden else { return }
        running.unhide()
    }

    /// Bring the app back to the user: unhidden, and frontmost when asked.
    func reveal(_ bundleID: String, activate: Bool) {
        guard let running = runningApp(bundleID) else { return }
        if running.isHidden {
            running.unhide()
        }
        if activate {
            running.activate()
        }
    }

    private func teardown() {
        backstopTimer?.invalidate()
        backstopTimer = nil
        if let hideObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(hideObserver)
            self.hideObserver = nil
        }
    }

    private func installHideObserverIfNeeded() {
        guard hideObserver == nil else { return }
        hideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }
            MainActor.assumeIsolated {
                guard let self, self.keptBundleIDs.contains(bundleID) else { return }
                self.unhide(bundleID)
            }
        }
    }

    private func startBackstopIfNeeded() {
        guard backstopTimer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.backstopInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for bundleID in self.keptBundleIDs {
                    self.unhide(bundleID)
                }
            }
        }
        timer.tolerance = Self.backstopInterval * 0.5
        backstopTimer = timer
    }
}
