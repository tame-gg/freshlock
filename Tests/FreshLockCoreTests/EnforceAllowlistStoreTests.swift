import Foundation
import FreshLockEnforce
import Testing

struct EnforceAllowlistStoreTests {
    @Test func roundTripsAllowlistJSONAtomically() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreshLockEnforceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = EnforceAllowlistStore(fileURL: dir.appendingPathComponent("allowlist.json"))
        let original = UnlockAllowlist(allowedSigningIDs: ["com.example.a", "com.example.b"])
        try store.save(original)
        let loaded = try store.load()
        #expect(loaded.allowedSigningIDs == original.allowedSigningIDs)
    }

    @Test func missingFileYieldsEmptyAllowlist() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-allowlist-\(UUID().uuidString).json")
        let store = EnforceAllowlistStore(fileURL: url)
        let loaded = try store.load()
        #expect(loaded.allowedSigningIDs.isEmpty)
    }
}
