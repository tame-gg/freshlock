//
//  UnlockStateStoreTests.swift
//  AppLockCoreTests
//

import Testing
import Foundation
@testable import AppLockCore

@MainActor
struct UnlockStateStoreTests {
    @Test func startsLocked() {
        let store = UnlockStateStore()
        #expect(store.isUnlocked("com.example.app") == false)
    }

    @Test func grantThenUnlocked() {
        let store = UnlockStateStore()
        store.grantUnlock("com.example.app", scope: .untilSleep)
        #expect(store.isUnlocked("com.example.app"))
    }

    @Test func lockAllClearsEverything() {
        let store = UnlockStateStore()
        store.grantUnlock("a", scope: .untilSleep)
        store.grantUnlock("b", scope: .untilLogout)
        store.lockAll()
        #expect(store.unlockedBundleIDs.isEmpty)
    }

    @Test func durationGrantExpiresByTime() {
        var now = Date(timeIntervalSince1970: 0)
        let store = UnlockStateStore { now }
        store.grantUnlock("a", scope: .forDuration(60))
        #expect(store.isUnlocked("a"))
        now = Date(timeIntervalSince1970: 61)
        #expect(store.isUnlocked("a") == false)
    }

    @Test func revokeMatchingScope() {
        let store = UnlockStateStore()
        store.grantUnlock("sleepy", scope: .untilSleep)
        store.grantUnlock("loggy", scope: .untilLogout)
        store.revokeGrants { scope in
            if case .untilSleep = scope { return true }
            return false
        }
        #expect(store.isUnlocked("sleepy") == false)
        #expect(store.isUnlocked("loggy"))
    }
}
