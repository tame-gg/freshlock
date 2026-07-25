//
//  ConfigurationTests.swift
//  AppLockCoreTests
//

import Testing
import Foundation
@testable import AppLockCore

struct ConfigurationTests {
    @Test func roundTripsThroughJSON() throws {
        var config = Configuration()
        config.protectedApps = [
            ProtectedApp(bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app",
                         isEnabled: true, isFavorite: true, category: .productivity, relockPolicy: .afterMinutes(5))
        ]
        config.settings.requireEveryLaunch = true

        let data = try config.encoded()
        let decoded = try Configuration.decoded(from: data)
        #expect(decoded == config)
    }

    @Test func rejectsFutureSchema() throws {
        var config = Configuration()
        config.schemaVersion = Configuration.currentSchemaVersion + 1
        let data = try config.encoded()
        #expect(throws: ConfigurationError.self) {
            _ = try Configuration.decoded(from: data)
        }
    }

    @Test func effectivePolicyResolvesOverride() {
        let withOverride = ProtectedApp(bundleIdentifier: "a", name: "A", path: "/A.app", relockPolicy: .manualOnly)
        #expect(withOverride.effectiveRelockPolicy(default: .afterSleep) == .manualOnly)

        let withoutOverride = ProtectedApp(bundleIdentifier: "b", name: "B", path: "/B.app")
        #expect(withoutOverride.effectiveRelockPolicy(default: .afterSleep) == .afterSleep)
    }
}

struct SettingsServiceTests {
    @Test func savesAndLoadsFromTempDirectory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let service = FileSettingsService(directory: dir)

        // Empty on first load.
        #expect(try service.load().protectedApps.isEmpty)

        var config = Configuration()
        config.protectedApps = [ProtectedApp(bundleIdentifier: "x", name: "X", path: "/X.app")]
        try service.save(config)

        let reloaded = try service.load()
        #expect(reloaded.protectedApps.count == 1)
        #expect(reloaded.protectedApp(for: "x")?.name == "X")

        try? FileManager.default.removeItem(at: dir)
    }
}
