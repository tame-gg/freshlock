//
//  RelockPolicyTests.swift
//  FreshLockCoreTests
//

import Foundation
import Testing
@testable import FreshLockCore

struct RelockPolicyTests {
    @Test func minutesAccessor() {
        #expect(RelockPolicy.afterMinutes(10).minutes == 10)
        #expect(RelockPolicy.afterInactivity(7).minutes == 7)
        #expect(RelockPolicy.afterSleep.minutes == nil)
        #expect(RelockPolicy.everyLaunch.minutes == nil)
    }

    @Test func allPoliciesGrantLastingUnlock() {
        // Every policy caches its unlock for its own window; requireEveryLaunch
        // forces relock on switch-away rather than destroying a live grant.
        for policy in [RelockPolicy.everyLaunch, .afterMinutes(5), .manualOnly, .afterSwitchingAway] {
            #expect(policy.grantsLastingUnlock)
        }
    }

    @Test func defaultMatchesiOSSwitchAway() {
        #expect(RelockPolicy.default == .afterSwitchingAway)
    }

    @Test func roundTripsThroughCodable() throws {
        for policy in [
            RelockPolicy.everyLaunch,
            .afterMinutes(15),
            .afterSleep,
            .afterScreenLock,
            .afterInactivity(3),
            .afterSwitchingAway,
            .manualOnly
        ] {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(RelockPolicy.self, from: data)
            #expect(decoded == policy)
        }
    }
}
