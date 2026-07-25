//
//  EnforceLockedSetStoreTests.swift
//  FreshLockCoreTests
//

import Foundation
import FreshLockEnforce
import Testing

struct EnforceLockedSetStoreTests {
    @Test func roundTripsLockedSet() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreshLockLockedSet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = EnforceLockedSetStore(fileURL: dir.appendingPathComponent("locked.json"))
        let original: Set<String> = ["com.example.mail", "com.example.notes"]
        try store.save(original)
        let loaded = try store.load()
        #expect(loaded == original)
    }

    @Test func missingFileYieldsEmptySet() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-locked-\(UUID().uuidString).json")
        let store = EnforceLockedSetStore(fileURL: url)
        #expect(try store.load().isEmpty)
    }
}
