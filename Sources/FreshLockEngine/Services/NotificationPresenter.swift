//
//  NotificationPresenter.swift
//  FreshLock
//
//  Posts user-facing notifications (e.g. "Safari launched and was locked").
//  Uses the modern `UserNotifications` framework. Notification permission is
//  requested lazily on first use.
//

import FreshLockCore
import Foundation
import UserNotifications

@MainActor
final class NotificationPresenter {
    static let shared = NotificationPresenter()
    private var authorized = false

    private init() {}

    /// `UNUserNotificationCenter` requires a code-signed app *bundle*; calling it
    /// from a bare executable (e.g. a raw `swift run` binary) raises an
    /// uncaught Objective-C exception. Guard on bundle identity so notifications
    /// simply no-op in that context instead of crashing the process.
    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorizationIfNeeded() async {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.general.error("Notification auth failed: \(error.localizedDescription)")
        }
    }

    func notifyProtectedLaunch(appName: String) {
        guard notificationsAvailable else { return }
        Task {
            if !authorized { await requestAuthorizationIfNeeded() }
            guard authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "FreshLock"
            content.body = "\(appName) launched and is locked."
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
