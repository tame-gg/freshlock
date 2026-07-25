//
//  AppDiscoveryServiceTests.swift
//  AppLockCoreTests
//
//  Exercises discovery against a synthetic `.app` bundle in a temp directory,
//  so the test is hermetic and doesn't depend on what's installed on the host.
//

import Testing
import Foundation
@testable import AppLockCore

struct AppDiscoveryServiceTests {
    /// Build a minimal `.app` bundle with the given Info.plist keys.
    private func makeBundle(in dir: URL, name: String, bundleID: String, version: String) throws -> URL {
        let app = dir.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test func discoversBundlesAndReadsMetadata() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try makeBundle(in: dir, name: "Zeta", bundleID: "com.example.zeta", version: "2.0")
        _ = try makeBundle(in: dir, name: "Alpha", bundleID: "com.example.alpha", version: "1.0")

        let service = AppDiscoveryService(searchPaths: [dir])
        let apps = service.discoverApps()

        #expect(apps.count == 2)
        // Sorted alphabetically by name.
        #expect(apps.first?.name == "Alpha")
        let zeta = apps.first { $0.bundleIdentifier == "com.example.zeta" }
        #expect(zeta?.version == "2.0")
    }

    @Test func ignoresNonAppEntries() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "hello".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        _ = try makeBundle(in: dir, name: "Real", bundleID: "com.example.real", version: "1.0")

        let apps = AppDiscoveryService(searchPaths: [dir]).discoverApps()
        #expect(apps.map(\.bundleIdentifier) == ["com.example.real"])
    }
}

struct AuthErrorMappingTests {
    @Test func retryabilityFlags() {
        #expect(AuthError.authenticationFailed.isRetryable)
        #expect(!AuthError.biometryNotEnrolled.isRetryable)
    }
}
