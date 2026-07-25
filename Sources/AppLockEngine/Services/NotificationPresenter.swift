//
//  NotificationPresenter.swift
//  AppLock
//
//  Posts user-facing notifications (e.g. "Safari launched and was locked").
//  Uses the modern `UserNotifications` framework. Notification permission is
//  requested lazily on first use.
//

import AppLockCore
import Foundation
import UserNotifications

@MainActor
final class NotificationPresenter {
    static let shared = NotificationPresenter()
    private var authorized = false

    private init() {}

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.general.error("Notification auth failed: \(error.localizedDescription)")
        }
    }

    func notifyProtectedLaunch(appName: String) {
        Task {
            if !authorized { await requestAuthorizationIfNeeded() }
            guard authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "AppLock"
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
