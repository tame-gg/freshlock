//
//  RelockPolicyTests.swift
//  AppLockCoreTests
//

import Testing
import Foundation
@testable import AppLockCore

struct RelockPolicyTests {
    @Test func minutesAccessor() {
        #expect(RelockPolicy.afterMinutes(10).minutes == 10)
        #expect(RelockPolicy.afterInactivity(7).minutes == 7)
        #expect(RelockPolicy.afterSleep.minutes == nil)
        #expect(RelockPolicy.everyLaunch.minutes == nil)
    }

    @Test func lastingUnlockSemantics() {
        #expect(RelockPolicy.everyLaunch.grantsLastingUnlock == false)
        #expect(RelockPolicy.afterMinutes(5).grantsLastingUnlock)
        #expect(RelockPolicy.manualOnly.grantsLastingUnlock)
        #expect(RelockPolicy.afterSwitchingAway.grantsLastingUnlock)
    }

    @Test func roundTripsThroughCodable() throws {
        for policy in [RelockPolicy.everyLaunch, .afterMinutes(15), .afterSleep,
                       .afterScreenLock, .afterInactivity(3), .afterSwitchingAway, .manualOnly] {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(RelockPolicy.self, from: data)
            #expect(decoded == policy)
        }
    }
}
