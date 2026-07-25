//
//  LoginItemService.swift
//  AppLock
//
//  Registers AppLock as a Login Item using `SMAppService`, the modern
//  (macOS 13+) replacement for the deprecated `SMLoginItemSetEnabled`. This is
//  what keeps protection alive across reboots without a separate installer.
//

import Foundation
import ServiceManagement
import AppLockCore

@MainActor
protocol LoginItemServiceProtocol: AnyObject {
    var isEnabled: Bool { get }
    /// Enable or disable launch-at-login. Throws if the system rejects it
    /// (e.g. the app isn't in /Applications, or the user denied it).
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class LoginItemService: LoginItemServiceProtocol {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if service.status != .enabled {
                try service.register()
                Log.lifecycle.info("Registered login item")
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
                Log.lifecycle.info("Unregistered login item")
            }
        }
    }
}
