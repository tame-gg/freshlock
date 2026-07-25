//
//  ProcessIdentity.swift
//  FreshLockEnforce
//
//  Identity used at the exec gate. Endpoint Security exposes signing_id /
//  team_id / cdhash — not CFBundleIdentifier as a first-class field. For
//  modern apps signing_id usually equals the bundle ID; policy code treats
//  them as aligned but documents the caveat.
//

import Foundation

/// Process identity as seen by an exec gate (ES or a test double).
public struct ProcessIdentity: Hashable, Sendable, Codable {
    /// Typically matches `CFBundleIdentifier` for modern apps.
    public var signingID: String

    /// Apple Developer Team ID when present.
    public var teamID: String?

    /// Optional code-directory hash (strongest, brittle across updates).
    public var cdhash: String?

    /// Executable path (weak identity; useful for logging only).
    public var executablePath: String?

    public init(
        signingID: String,
        teamID: String? = nil,
        cdhash: String? = nil,
        executablePath: String? = nil
    ) {
        self.signingID = signingID
        self.teamID = teamID
        self.cdhash = cdhash
        self.executablePath = executablePath
    }
}

/// Result of an exec-gate decision.
public enum ExecDecision: String, Sendable, Equatable {
    case allow
    case deny
}
