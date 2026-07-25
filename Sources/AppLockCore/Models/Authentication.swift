//
//  Authentication.swift
//  AppLockCore
//
//  Value types describing authentication requests, methods and results. The
//  actual biometric prompt is performed by `AuthenticationService` using
//  Apple's LocalAuthentication framework — these types are the framework-free
//  vocabulary the rest of the app speaks.
//

import Foundation

/// The biometric/credential method that satisfied (or is available for) an
/// authentication.
///
/// Note: LocalAuthentication does not expose Apple Watch as a *distinct*
/// biometry type — watch unlock is surfaced through the same
/// `deviceOwnerAuthentication` policy as the password fallback. We model it
/// separately for UI copy, but the framework decides which is actually used.
public enum AuthMethod: String, Codable, Hashable, Sendable {
    case touchID
    case watch
    case password
    case unavailable

    public var displayName: String {
        switch self {
        case .touchID: "Touch ID"
        case .watch: "Apple Watch"
        case .password: "Password"
        case .unavailable: "Unavailable"
        }
    }
}

/// The outcome of an authentication attempt.
public enum AuthResult: Equatable, Sendable {
    case success(AuthMethod)
    case failure(AuthError)
    /// The user actively cancelled (tapped Cancel / hit Esc).
    case cancelled
}

/// A framework-independent error surface for authentication failures. Maps from
/// `LAError` at the service boundary so callers never import LocalAuthentication.
public enum AuthError: Error, Equatable, Sendable {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case authenticationFailed
    case passcodeNotSet
    case systemCancel
    case userFallbackRequested
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .authenticationFailed, .systemCancel: true
        default: false
        }
    }
}
