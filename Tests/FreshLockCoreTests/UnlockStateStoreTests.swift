//
//  UnlockStateStoreTests.swift
//  FreshLockCoreTests
//

import Foundation
import Testing
@testable import FreshLockCore

@MainActor
struct UnlockStateStoreTests {
    @Test func startsLocked() {
        let store = UnlockStateStore()
        #expect(store.isUnlocked("com.example.app", pid: 1) == false)
    }

    @Test func grantThenUnlockedOnlyForThatPID() {
        let store = UnlockStateStore()
        store.grantUnlock("com.example.app", scope: .untilSleep, sessionPID: 42)
        #expect(store.isUnlocked("com.example.app", pid: 42))
        #expect(store.isUnlocked("com.example.app", pid: 99) == false)
        // Mismatch must not destroy the grant for the authenticating process.
        #expect(store.hasGrant("com.example.app"))
        #expect(store.isUnlocked("com.example.app", pid: 42))
    }

    @Test func quitAndRelaunchRequiresAuth() {
        let store = UnlockStateStore()
        store.grantUnlock("com.apple.MobileSMS", scope: .untilSleep, sessionPID: 100)
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 100))

        // Process 100 exited; nothing live for this bundle.
        let revoked = store.revokeDeadSessions(livePIDsByBundle: [:])
        #expect(revoked == ["com.apple.MobileSMS"])
        #expect(store.hasGrant("com.apple.MobileSMS") == false)

        // Relaunch under a new PID — must authenticate again.
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 200) == false)
    }

    @Test func pidReplaceWithoutNilGapRevokes() {
        let store = UnlockStateStore()
        store.grantUnlock("com.apple.MobileSMS", scope: .untilLogout, sessionPID: 100)
        // Quit notification missed; poll sees only the new PID.
        let revoked = store.revokeDeadSessions(
            livePIDsByBundle: ["com.apple.MobileSMS": [200]]
        )
        #expect(revoked == ["com.apple.MobileSMS"])
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 200) == false)
    }

    @Test func overlappingPIDsKeepGrantForLiveSession() {
        let store = UnlockStateStore()
        store.grantUnlock("com.apple.MobileSMS", scope: .untilSleep, sessionPID: 100)
        // Old and new briefly coexist; grant for 100 stays while 100 is live.
        let revoked = store.revokeDeadSessions(
            livePIDsByBundle: ["com.apple.MobileSMS": [100, 200]]
        )
        #expect(revoked.isEmpty)
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 100))
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 200) == false)
    }

    @Test func lockAllClearsEverything() {
        let store = UnlockStateStore()
        store.grantUnlock("a", scope: .untilSleep, sessionPID: 1)
        store.grantUnlock("b", scope: .untilLogout, sessionPID: 2)
        store.lockAll()
        #expect(store.unlockedBundleIDs.isEmpty)
    }

    @Test func durationGrantExpiresByTime() {
        var now = Date(timeIntervalSince1970: 0)
        let store = UnlockStateStore { now }
        store.grantUnlock("a", scope: .forDuration(60), sessionPID: 1)
        #expect(store.isUnlocked("a", pid: 1))
        now = Date(timeIntervalSince1970: 61)
        #expect(store.isUnlocked("a", pid: 1) == false)
    }

    @Test func inactivityGrantDoesNotExpireByWallClock() {
        var now = Date(timeIntervalSince1970: 0)
        let store = UnlockStateStore { now }
        store.grantUnlock("a", scope: .untilInactivity(300), sessionPID: 1)
        #expect(store.isUnlocked("a", pid: 1))
        now = Date(timeIntervalSince1970: 10_000)
        // Idle expiry is handled by RelockManager via CGEventSource, not wall clock.
        #expect(store.isUnlocked("a", pid: 1))
    }

    @Test func gracePeriodTracksGrantedAt() {
        var now = Date(timeIntervalSince1970: 100)
        let store = UnlockStateStore { now }
        store.grantUnlock("a", scope: .untilSleep, sessionPID: 1)
        let grant = store.grants["a"]!
        #expect(grant.isWithinGracePeriod(5, asOf: now))
        now = Date(timeIntervalSince1970: 104)
        #expect(grant.isWithinGracePeriod(5, asOf: now))
        now = Date(timeIntervalSince1970: 106)
        #expect(grant.isWithinGracePeriod(5, asOf: now) == false)
        #expect(grant.isWithinGracePeriod(0, asOf: now) == false)
    }

    @Test func revokeInactivityScope() {
        let store = UnlockStateStore()
        store.grantUnlock("idle", scope: .untilInactivity(60), sessionPID: 1)
        store.grantUnlock("awake", scope: .untilSleep, sessionPID: 2)
        store.revokeGrants { $0.inactivityThreshold != nil }
        #expect(store.isUnlocked("idle", pid: 1) == false)
        #expect(store.isUnlocked("awake", pid: 2))
    }

    @Test func revokeMatchingScope() {
        let store = UnlockStateStore()
        store.grantUnlock("sleepy", scope: .untilSleep, sessionPID: 1)
        store.grantUnlock("loggy", scope: .untilLogout, sessionPID: 2)
        store.revokeGrants { scope in
            if case .untilSleep = scope {
                return true
            }
            return false
        }
        #expect(store.isUnlocked("sleepy", pid: 1) == false)
        #expect(store.isUnlocked("loggy", pid: 2))
    }

    @Test func terminateThenLaunchIsNewSession() {
        let store = UnlockStateStore()
        store.grantUnlock("com.apple.MobileSMS", scope: .untilSleep, sessionPID: 50)
        store.lock("com.apple.MobileSMS") // didTerminate
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 50) == false)
        #expect(store.isUnlocked("com.apple.MobileSMS", pid: 51) == false)
    }
}
