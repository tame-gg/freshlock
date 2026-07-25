//
//  AppMonitorService.swift
//  FreshLock
//
//  Detects application launches and activations using `NSWorkspace`
//  notifications. This is the public, notification-driven way to observe app
//  lifecycle on macOS. Window-level detail (create / move / resize) is handled
//  separately by `AccessibilityService` once a protected app is being secured.
//
//  macOS honesty note: `NSWorkspace` notifications fire *after* an app has
//  begun launching; there is no public API to *prevent* a launch or to receive
//  a pre-launch veto. FreshLock therefore reacts as fast as the OS allows — on
//  the activation/launch notification — and immediately covers the app with an
//  overlay. It cannot guarantee that not a single frame of the protected app
//  was drawn before the overlay appears. This limitation is documented in
//  docs/TROUBLESHOOTING.md and ARCHITECTURE.md.
//

import AppKit
import Combine
import Foundation
import FreshLockCore

/// A high-level lifecycle event about a running application.
/// Bundle ID is the persistent app identity; PID identifies the live process
/// for that event (required for terminate so grants bound to other instances
/// of the same bundle are not cleared incorrectly).
enum AppLifecycleEvent: Sendable {
    case launched(bundleID: String, pid: pid_t)
    case activated(bundleID: String, pid: pid_t)
    case terminated(bundleID: String, pid: pid_t)
}

@MainActor
protocol AppMonitorServiceProtocol: AnyObject {
    /// Emits lifecycle events for *all* apps; the coordinator filters to the
    /// protected set. Starts emitting once `start()` is called.
    var events: AnyPublisher<AppLifecycleEvent, Never> { get }
    func start()
    func stop()
}

/// `NSWorkspace`-backed implementation.
@MainActor
final class AppMonitorService: AppMonitorServiceProtocol {
    private let subject = PassthroughSubject<AppLifecycleEvent, Never>()
    private var observers: [NSObjectProtocol] = []
    private let workspace: NSWorkspace

    var events: AnyPublisher<AppLifecycleEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = workspace.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let info = Self.info(from: note) else { return }
            MainActor.assumeIsolated {
                self?.subject.send(.launched(bundleID: info.bundleID, pid: info.pid))
            }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let info = Self.info(from: note) else { return }
            MainActor.assumeIsolated {
                self?.subject.send(.activated(bundleID: info.bundleID, pid: info.pid))
            }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let info = Self.info(from: note) else { return }
            MainActor.assumeIsolated {
                self?.subject.send(.terminated(bundleID: info.bundleID, pid: info.pid))
            }
        })

        Log.monitor.info("App monitor started")
    }

    func stop() {
        let center = workspace.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        Log.monitor.info("App monitor stopped")
    }

    /// Extract the plain, `Sendable` fields we need from a workspace
    /// notification. Doing this synchronously in the (main-queue) handler avoids
    /// sending the non-`Sendable` `Notification` across the actor boundary.
    private nonisolated static func info(from note: Notification) -> (bundleID: String, pid: pid_t)? {
        guard
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleID = app.bundleIdentifier
        else { return nil }
        return (bundleID, app.processIdentifier)
    }

    deinit {
        // Observers are cleaned up by the notification center on dealloc; we
        // avoid touching main-actor state here.
    }
}
