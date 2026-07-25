//
//  EnforceExtensionMain.swift
//  FreshLockEnforceExtension
//
//  Entry point for the Endpoint Security enforce client.
//
//  Deliberately not named main.swift: a file with that name is treated as
//  top-level code, which makes `@main` illegal in the module.
//
//  In production this binary lives inside a `.systemextension` bundle under
//  FreshLock.app/Contents/Library/SystemExtensions/. Build it with
//  Scripts/build-systemextension.sh (optionally embed via EMBED_SYSTEM_EXTENSION=1).
//
//  Without Apple's managed ES entitlement (or FDA / privilege), es_new_client
//  fails: we log clearly and exit 0 so accidental runs are not treated as crashes.
//  That is fail-clean, not fail-closed — without an ES client there is no kernel
//  gate to hold. Phase 0 overlays remain the shipping deterrent.
//

import Foundation
import FreshLockEnforce
import os.log

@main
enum FreshLockEnforceExtensionMain {
    private static let log = Logger(subsystem: "gg.tame.freshlock.enforce", category: "main")

    static func main() {
        log.notice("FreshLockEnforceExtension starting")

        let allowlistStore = Self.resolveAllowlistStore()
        let lockedStore = Self.resolveLockedStore()
        let lockedIDs = (try? lockedStore.load()) ?? []
        let policy = ExecGatePolicy(lockedSigningIDs: lockedIDs)
        if lockedIDs.isEmpty {
            log.notice("Locked set empty — AUTH_EXEC would ALLOW-all until the host publishes protected apps")
        }

        let client = EndpointSecurityClient(policy: policy, allowlistStore: allowlistStore, lockedStore: lockedStore)

        do {
            try client.start()
        } catch let error as ESClientStartError {
            // Fail clean: entitlement / FDA / privilege missing. Do not crash.
            log.error("ES client unavailable: \(error.description, privacy: .public)")
            log.error("Phase 1 not active. Kernel kexts are not used; see docs/ENFORCEMENT.md.")
            fputs("FreshLockEnforceExtension: \(error.description)\n", stderr)
            fputs("Phase 1 not active (fail-clean). See docs/ENFORCEMENT.md.\n", stderr)
            exit(EXIT_SUCCESS)
        } catch {
            log.error("ES client failed: \(String(describing: error), privacy: .public)")
            fputs("FreshLockEnforceExtension: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }

        // Reload locked set + allowlist until XPC control plane is fully wired.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            client.reloadFromDisk()
        }
        timer.resume()

        log.notice("ES AUTH_EXEC gate running — Ctrl+C to stop (standalone) or unload sysext")
        dispatchMain()
    }

    /// Prefer machine-shared paths when readable (sysext as root); else user domain.
    private static func resolveAllowlistStore() -> EnforceAllowlistStore {
        let shared = EnforceAllowlistStore.sharedLibraryURL()
        if FileManager.default.isReadableFile(atPath: shared.fileURL.path)
            || FileManager.default.fileExists(atPath: shared.fileURL.deletingLastPathComponent().path)
        {
            // Use shared if the directory exists or the process can create it (root).
            if FileManager.default.isWritableFile(atPath: "/Library/Application Support")
                || FileManager.default.fileExists(atPath: shared.fileURL.path)
            {
                return shared
            }
        }
        return .defaultURL()
    }

    private static func resolveLockedStore() -> EnforceLockedSetStore {
        let shared = EnforceLockedSetStore.sharedLibraryURL()
        if FileManager.default.isWritableFile(atPath: "/Library/Application Support")
            || FileManager.default.fileExists(atPath: shared.fileURL.path)
        {
            return shared
        }
        return .defaultURL()
    }
}
