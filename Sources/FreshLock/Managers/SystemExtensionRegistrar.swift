//
//  SystemExtensionRegistrar.swift
//  FreshLock
//
//  Host-side scaffolding for activating / deactivating the Endpoint Security
//  system extension via OSSystemExtensionRequest.
//
//  This compiles and runs without Apple's ES entitlement: activation will fail
//  with a clear status. SMAppService is used for the Phase 0 login-item helper
//  only — system extensions require SystemExtensions.framework, not SMAppService.
//

import Foundation
import FreshLockEnforce
import os.log
import SystemExtensions

private let log = Logger(subsystem: "gg.tame.freshlock", category: "SystemExtension")

/// Result surfaced to Preferences / onboarding UI.
public enum SystemExtensionRegistrationStatus: Equatable, Sendable {
    case idle
    case submitting
    case needsUserApproval
    case activated
    case deactivated
    case failed(String)
    case notEmbedded

    public var displayText: String {
        switch self {
        case .idle:
            "Not requested"
        case .submitting:
            "Submitting request…"
        case .needsUserApproval:
            "Waiting for approval in System Settings → Privacy & Security"
        case .activated:
            "Activated (still needs ES entitlement + Full Disk Access to enforce)"
        case .deactivated:
            "Deactivated"
        case let .failed(message):
            message
        case .notEmbedded:
            "System extension not embedded (build with EMBED_SYSTEM_EXTENSION=1)"
        }
    }
}

/// Wraps `OSSystemExtensionRequest` for the FreshLock Enforce extension.
@MainActor
public final class SystemExtensionRegistrar: NSObject, ObservableObject {
    @Published public private(set) var status: SystemExtensionRegistrationStatus = .idle

    public let extensionIdentifier: String

    private var pendingRequest: OSSystemExtensionRequest?
    private var pendingIsActivation = true

    public init(extensionIdentifier: String = EnforceGatePaths.extensionBundleIdentifier) {
        self.extensionIdentifier = extensionIdentifier
        super.init()
    }

    /// Whether `Contents/Library/SystemExtensions/*.systemextension` exists in the host.
    public var isExtensionEmbedded: Bool {
        Self.embeddedSystemExtensionURLs().isEmpty == false
    }

    public static func embeddedSystemExtensionURLs(
        bundle: Bundle = .main
    ) -> [URL] {
        guard let builtIn = bundle.builtInPlugInsURL?.deletingLastPathComponent()
            .appendingPathComponent("Library/SystemExtensions", isDirectory: true)
        else {
            // Fall back to Contents/Library/SystemExtensions relative to executable.
            guard let exe = bundle.executableURL else { return [] }
            let sysExtDir = exe
                .deletingLastPathComponent() // MacOS
                .deletingLastPathComponent() // Contents
                .appendingPathComponent("Library/SystemExtensions", isDirectory: true)
            return systemExtensionBundles(in: sysExtDir)
        }
        return systemExtensionBundles(in: builtIn)
    }

    private static func systemExtensionBundles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "systemextension" }
    }

    public func activate() {
        guard isExtensionEmbedded else {
            status = .notEmbedded
            log.notice("Activate skipped: no .systemextension in the app bundle")
            return
        }
        status = .submitting
        pendingIsActivation = true
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        pendingRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
        let identifier = extensionIdentifier
        log.notice("Submitted activation request for \(identifier, privacy: .public)")
    }

    public func deactivate() {
        guard isExtensionEmbedded else {
            status = .notEmbedded
            return
        }
        status = .submitting
        pendingIsActivation = false
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionIdentifier,
            queue: .main
        )
        request.delegate = self
        pendingRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
        let identifier = extensionIdentifier
        log.notice("Submitted deactivation request for \(identifier, privacy: .public)")
    }

    public func refreshEmbeddedProbe() {
        if !isExtensionEmbedded, status == .idle {
            // Keep idle; Preferences shows a separate "not embedded" line.
        }
    }
}

extension SystemExtensionRegistrar: OSSystemExtensionRequestDelegate {
    public nonisolated func request(
        _: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            pendingRequest = nil
            switch result {
            case .completed:
                status = pendingIsActivation ? .activated : .deactivated
                log.notice("System extension request completed")
            case .willCompleteAfterReboot:
                status = .failed("Will complete after reboot")
            @unknown default:
                status = .failed("Unknown result \(result.rawValue)")
            }
        }
    }

    public nonisolated func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            pendingRequest = nil
            let message = error.localizedDescription
            status = .failed(message)
            log.error("System extension request failed: \(message, privacy: .public)")
        }
    }

    public nonisolated func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
        Task { @MainActor in
            status = .needsUserApproval
            log.notice("System extension needs user approval in System Settings")
        }
    }

    public nonisolated func request(
        _: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        let from = existing.bundleIdentifier
        let to = ext.bundleIdentifier
        log.notice(
            "Replacing system extension \(from, privacy: .public) with \(to, privacy: .public)"
        )
        return .replace
    }
}
