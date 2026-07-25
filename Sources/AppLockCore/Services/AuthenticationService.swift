//
//  AuthenticationService.swift
//  AppLockCore
//
//  The one and only place AppLock talks to biometrics. We use Apple's
//  `LocalAuthentication` framework and its *native* evaluation UI — AppLock
//  never draws its own password field, never sees a password, and never stores
//  a credential.
//
//  macOS honesty note: LocalAuthentication does not distinguish Apple Watch as
//  a `LABiometryType`. `deviceOwnerAuthentication` transparently accepts Touch
//  ID, a nearby unlocked Apple Watch (on supported Macs), *or* the account
//  password. We therefore report the *available* method from `biometryType`,
//  but the system decides which factor actually satisfies the prompt.
//

import Foundation
import LocalAuthentication

/// Abstraction over biometric authentication, so views/managers can be tested
/// against a stub.
public protocol AuthenticationServiceProtocol: Sendable {
    /// The biometry available on this device, for UI copy ("Unlock with …").
    func availableMethod() -> AuthMethod

    /// Present Apple's native authentication sheet with the given reason.
    /// - Parameter reason: user-facing justification (Apple requires this).
    /// - Returns: the result of the attempt. Never throws for "wrong finger" —
    ///   that is surfaced as `.failure`.
    func authenticate(reason: String) async -> AuthResult
}

/// Production implementation backed by `LAContext`.
public struct LocalAuthenticationService: AuthenticationServiceProtocol {
    /// The policy to evaluate. `deviceOwnerAuthentication` includes the password
    /// fallback (and Apple Watch), which is exactly what we want — the user can
    /// always fall back to their Mac password.
    private let policy: LAPolicy

    public init(policy: LAPolicy = .deviceOwnerAuthentication) {
        self.policy = policy
    }

    public func availableMethod() -> AuthMethod {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics enrolled/available, but password may still work.
            let fallback = LAContext()
            if fallback.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return .password
            }
            return .unavailable
        }
        switch context.biometryType {
        case .touchID: return .touchID
        default: return .password
        }
    }

    public func authenticate(reason: String) async -> AuthResult {
        // A fresh context per attempt: contexts cache evaluation and we want
        // each lock prompt to be a genuine, independent challenge.
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var canEvalError: NSError?
        guard context.canEvaluatePolicy(policy, error: &canEvalError) else {
            let mapped = Self.mapError(canEvalError)
            Log.auth.error("Cannot evaluate policy: \(String(describing: mapped))")
            return .failure(mapped)
        }

        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            if ok {
                let method = availableMethod()
                Log.auth.info("Authentication succeeded via \(method.displayName)")
                return .success(method)
            }
            return .failure(.authenticationFailed)
        } catch let laError as LAError {
            if laError.code == .userCancel || laError.code == .appCancel {
                return .cancelled
            }
            if laError.code == .userFallback {
                return .failure(.userFallbackRequested)
            }
            return .failure(Self.mapError(laError as NSError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    /// Translate an `LAError`/`NSError` into our framework-free `AuthError`.
    static func mapError(_ error: NSError?) -> AuthError {
        guard let error else { return .unknown("nil error") }
        guard let code = LAError.Code(rawValue: error.code) else {
            return .unknown(error.localizedDescription)
        }
        switch code {
        case .biometryNotAvailable: return .biometryNotAvailable
        case .biometryNotEnrolled: return .biometryNotEnrolled
        case .biometryLockout: return .biometryLockout
        case .passcodeNotSet: return .passcodeNotSet
        case .authenticationFailed: return .authenticationFailed
        case .systemCancel: return .systemCancel
        case .userFallback: return .userFallbackRequested
        default: return .unknown(error.localizedDescription)
        }
    }
}
