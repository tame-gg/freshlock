//
//  LoginItemService.swift
//  FreshLock
//
//  Registers FreshLock as a Login Item using `SMAppService`, the modern
//  (macOS 13+) replacement for the deprecated `SMLoginItemSetEnabled`. This is
//  what keeps protection alive across reboots without a separate installer.
//

import Foundation
import ServiceManagement
import FreshLockCore

@MainActor
public protocol LoginItemServiceProtocol: AnyObject {
    var isEnabled: Bool { get }
    /// Enable or disable launch-at-login. Throws if the system rejects it
    /// (e.g. the app isn't in /Applications, or the user denied it).
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public final class LoginItemService: LoginItemServiceProtocol {
    private let service: SMAppService

    /// - Parameter service: the `SMAppService` to manage. Defaults to
    ///   ``SMAppService/mainApp``; the GUI passes ``SMAppService/agent(plistName:)``
    ///   to register the background helper instead.
    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var isEnabled: Bool {
        service.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
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
