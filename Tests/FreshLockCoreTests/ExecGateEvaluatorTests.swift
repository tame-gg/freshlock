//
//  ExecGateEvaluatorTests.swift
//  FreshLockCoreTests
//

import FreshLockEnforce
import Testing

struct ExecGateEvaluatorTests {
    @Test func allowsNonLocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.apple.Safari")) == .allow)
    }

    @Test func deniesLocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .deny)
    }

    @Test func allowsUnlocked() {
        let policy = ExecGatePolicy(lockedSigningIDs: ["com.example.mail"])
        let allowlist = UnlockAllowlist(allowedSigningIDs: ["com.example.mail"])
        let evaluator = ExecGateEvaluator(policy: policy, allowlist: allowlist)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: "com.example.mail")) == .allow)
    }

    @Test func alwaysAllowsSelf() {
        let policy = ExecGatePolicy(lockedSigningIDs: [ExecGatePolicy.freshLockSigningID])
        let evaluator = ExecGateEvaluator(policy: policy)
        #expect(evaluator.decision(for: ProcessIdentity(signingID: ExecGatePolicy.freshLockSigningID)) == .allow)
    }

    @Test func fromProtectedBundleIDsMapsIntoLockedSet() {
        let policy = ExecGatePolicy.fromProtectedBundleIDs(["a", "b"])
        #expect(policy.lockedSigningIDs == ["a", "b"])
    }
}
