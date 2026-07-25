//
//  EnforceControlXPC.swift
//  FreshLockEnforce
//
//  Control-plane protocol between FreshLock host/helper and the ES extension.
//  Scaffolding only — no listener is registered in Phase 0 shipping builds.
//

import Foundation

/// Mach service name reserved for the enforce control channel.
public enum EnforceXPCConstants {
    public static let machServiceName = "gg.tame.freshlock.enforce.xpc"

    /// Same as ``EnforceGatePaths/extensionBundleIdentifier``.
    public static let extensionBundleIdentifier = EnforceGatePaths.extensionBundleIdentifier
}

/// Host → extension: push policy / allowlist updates.
@objc public protocol EnforceControlHostProtocol {
    func replaceLockedSigningIDs(_ ids: [String], reply: @escaping @Sendable (Bool) -> Void)
    func replaceAllowlist(_ ids: [String], reply: @escaping @Sendable (Bool) -> Void)
    func ping(reply: @escaping @Sendable (String) -> Void)
}

/// Extension → host: optional callbacks (e.g. denied exec for UI).
@objc public protocol EnforceControlExtensionProtocol {
    func didDenyExec(signingID: String, path: String?)
}
