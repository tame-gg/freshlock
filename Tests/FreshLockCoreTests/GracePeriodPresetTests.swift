//
//  GracePeriodPresetTests.swift
//  FreshLockCoreTests
//

import Foundation
import Testing
@testable import FreshLockCore

struct GracePeriodPresetTests {
    @Test func presetsMapToExpectedSeconds() {
        #expect(GracePeriodPreset.fifteenSeconds.seconds == 15)
        #expect(GracePeriodPreset.thirtySeconds.seconds == 30)
        #expect(GracePeriodPreset.oneMinute.seconds == 60)
        #expect(GracePeriodPreset.fiveMinutes.seconds == 300)
        #expect(GracePeriodPreset.fifteenMinutes.seconds == 900)
    }

    @Test func matchingRecognizesPresetsOnly() {
        #expect(GracePeriodPreset.matching(30) == .thirtySeconds)
        #expect(GracePeriodPreset.matching(60) == .oneMinute)
        #expect(GracePeriodPreset.matching(45) == nil)
        #expect(GracePeriodPreset.matching(3) == nil)
    }

    @Test func unitConvertsToAndFromSeconds() {
        #expect(GracePeriodUnit.seconds.toSeconds(45) == 45)
        #expect(GracePeriodUnit.minutes.toSeconds(5) == 300)
        #expect(GracePeriodUnit.hours.toSeconds(1) == 3_600)
        #expect(GracePeriodUnit.minutes.toSeconds(-2) == 0)
    }

    @Test func preferredDisplayPicksLargestCleanUnit() {
        let hours = GracePeriodUnit.preferredDisplay(forSeconds: 7_200)
        #expect(hours.value == 2)
        #expect(hours.unit == .hours)

        let minutes = GracePeriodUnit.preferredDisplay(forSeconds: 300)
        #expect(minutes.value == 5)
        #expect(minutes.unit == .minutes)

        let seconds = GracePeriodUnit.preferredDisplay(forSeconds: 45)
        #expect(seconds.value == 45)
        #expect(seconds.unit == .seconds)
    }

    @Test func appSettingsDefaultGracePeriodIsThirtySeconds() throws {
        #expect(AppSettings.default.gracePeriodSeconds == 30)

        let missingKey = Data(
            """
            {
              "launchAtLogin": false,
              "defaultRelockPolicy": { "afterSwitchingAway": {} },
              "overlayStyle": "blur",
              "notifyOnProtectedLaunch": false,
              "requireEveryLaunch": false,
              "developerMode": false,
              "defaultInactivityMinutes": 5
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: missingKey)
        #expect(decoded.gracePeriodSeconds == 30)
    }
}
