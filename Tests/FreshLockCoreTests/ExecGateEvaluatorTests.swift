//
//  ExecGateEvaluatorTests.swift
//  FreshLockCoreTests
//

import FreshLockEnforce
import Testing

@Suite("ExecGateEvaluator")
struct ExecGateEvaluatorTests {
    @Test("unlocked and non-locked binaries are allowed")
    func allowsNonLocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.apple.Safari")) == .allow)
    }

    @Test("locked binary without allowlist entry is denied")
    func deniesLocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .deny)
    }

    @Test("locked binary on allowlist is allowed")
    func allowsUnlocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let allowlist = UnlockAllowlist(allowedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy, allowlist: allowlist)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .allow)
    }

    @Test("FreshLock signing IDs are always allowed")
    func alwaysAllowsSelf() {
        let policy = ExecGatePolicy(lockedSigningIDs: [ExecGatePolicy.freshLockSigningID])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: ExecGatePolicy.freshLockSigningID)) == .allow)
    }

    @Test("fromProtectedBundleIDs maps bundle IDs into locked set")
    func fromBundleIDs() {
        let policy = ExecGatePolicy.fromProtectedBundleIDs(["a", "b"])
        #expect(policy.lockedSigningIDs == ["a", "b"])
    }
}
