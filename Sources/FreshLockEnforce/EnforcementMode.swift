//
//  EnforcementMode.swift
//  FreshLockEnforce
//
//  Declares which enforcement plane is active. Phase 0 is overlays only.
//  Phase 1 is Endpoint Security AUTH_EXEC (requires Apple entitlement).
//

import Foundation

/// Which enforcement plane FreshLock is using.
///
/// - Important: ``overlayDeterrent`` is **not** kernel enforcement. Do not
///   describe it as such in UI or docs.
public enum EnforcementMode: String, Sendable, Codable, CaseIterable {
    /// Shipping behaviour: detect after launch, cover with overlay, LA auth.
    case overlayDeterrent

    /// Kernel-held exec deny via Endpoint Security `AUTH_EXEC`.
    /// Requires `com.apple.developer.endpoint-security.client` and a system
    /// extension. Not shipping until Apple entitles and packaging is wired.
    case endpointSecurityExecGate
}

/// Capability probe results for honest UI / logging.
public struct EnforcementCapabilities: Sendable, Equatable {
    /// Overlay + LA path is always available on macOS 15+ for this product.
    public let overlayDeterrentAvailable: Bool

    /// `true` only when the ES entitlement is present **and** an ES client can
    /// be created (privileged + FDA). Scaffolding reports `false` until then.
    public let endpointSecurityAvailable: Bool

    /// Human-readable reason ES is unavailable (entitlement, FDA, privilege, …).
    public let endpointSecurityUnavailableReason: String?

    public init(
        overlayDeterrentAvailable: Bool = true,
        endpointSecurityAvailable: Bool = false,
        endpointSecurityUnavailableReason: String? = "Endpoint Security client not entitled or not installed"
    ) {
        self.overlayDeterrentAvailable = overlayDeterrentAvailable
        self.endpointSecurityAvailable = endpointSecurityAvailable
        self.endpointSecurityUnavailableReason = endpointSecurityUnavailableReason
    }

    /// Default for current shipping builds: overlays only.
    public static let phase0Only = EnforcementCapabilities()
}
