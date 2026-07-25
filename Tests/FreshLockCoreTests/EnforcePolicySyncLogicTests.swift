//
//  EnforcePolicySyncLogicTests.swift
//  FreshLockCoreTests
//
//  Tests the grant → allowlist / locked-set mapping used by EnforcePolicySync
//  without needing AppKit or a live LockEngine.
//

import FreshLockEnforce
import Testing

struct EnforcePolicySyncLogicTests {
    @Test func evaluatorReflectsUnlockGrant() {
        let locked = Set(["com.example.mail", "com.example.notes"])
        let policy = ExecGatePolicy.fromProtectedBundleIDs(locked)
        var allowlist = UnlockAllowlist()
        var evaluator = ExecGateEvaluator(policy: policy, allowlist: allowlist)

        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .deny)

        allowlist = allowlist.allowing("com.example.mail")
        evaluator.allowlist = allowlist
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .allow)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.notes")) == .deny)
    }

    @Test func revokingUnlockReturnsToDeny() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        var allowlist = UnlockAllowlist(allowedSigningIDs: ["com.example.mail"])
        var evaluator = ExecGateEvaluator(policy: policy, allowlist: allowlist)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .allow)

        allowlist = allowlist.revoking("com.example.mail")
        evaluator.allowlist = allowlist
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .deny)
    }

    @Test func emptyLockedSetAllowsEverything() {
        let evaluator = ExecGateEvaluator(policy: ExecGatePolicy(lockedSigningIDs: []))
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.anything")) == .allow)
    }

    @Test func alwaysAllowBeatsLockedAndMissingAllowlist() {
        let policy = ExecGatePolicy(
            lockedSigningIDs: ["gg.tame.freshlock.helper"],
            alwaysAllowSigningIDs: ExecGatePolicy.defaultAlwaysAllow
        )
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "gg.tame.freshlock.helper")) == .allow)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "gg.tame.freshlock.enforce")) == .allow)
    }

    @Test func capabilitiesDefaultToPhase0() {
        let caps = EnforcementCapabilities.phase0Only
        #expect(caps.overlayDeterrentAvailable)
        #expect(!caps.endpointSecurityAvailable)
        #expect(!caps.systemExtensionEmbedded)
        #expect(caps.activeMode == .overlayDeterrent)
    }

    @Test func gatePathsMatchExtensionBundleID() {
        #expect(EnforceGatePaths.extensionBundleIdentifier == "gg.tame.freshlock.enforce")
        #expect(EnforceXPCConstants.extensionBundleIdentifier == EnforceGatePaths.extensionBundleIdentifier)
    }
}
