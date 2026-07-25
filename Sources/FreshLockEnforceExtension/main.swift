//
//  main.swift
//  FreshLockEnforceExtension
//
//  Entry point for the Endpoint Security enforce client.
//
//  In production this binary would live inside a `.systemextension` bundle
//  under FreshLock.app. Today it is a scaffold you can `swift build` and run
//  only in privileged/entitled environments (typically SIP-off for unsigned
//  ES clients during development).
//
//  Default behaviour without entitlement: log a clear failure and exit 0 so
//  accidental runs are not treated as crashes.
//

import Foundation
import FreshLockEnforce
import os.log

@main
enum FreshLockEnforceExtensionMain {
    private static let log = Logger(subsystem: "gg.tame.freshlock.enforce", category: "main")

    static func main() {
        log.notice("FreshLockEnforceExtension starting (Phase 1 scaffolding - not shipping enforcement)")

        let store = EnforceAllowlistStore.defaultURL()
        // Locked set starts empty until the host pushes policy / we read config.
        // An empty locked set means ALLOW-all - safe default for an unfinished wire-up.
        let policy = ExecGatePolicy(lockedSigningIDs: [])
        let client = EndpointSecurityClient(policy: policy, allowlistStore: store)

        do {
            try client.start()
        } catch let error as ESClientStartError {
            log.error("ES client unavailable: \(error.description, privacy: .public)")
            log.error("Phase 1 is not active. See docs/ENFORCEMENT.md and docs/THREAT_MODEL.md.")
            // Exit successfully: scaffolding is present; entitlement is not.
            exit(EXIT_SUCCESS)
        } catch {
            log.error("ES client failed: \(String(describing: error), privacy: .public)")
            exit(EXIT_FAILURE)
        }

        // Reload allowlist periodically until XPC control plane is wired.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            client.reloadAllowlist()
        }
        timer.resume()

        log.notice("ES AUTH_EXEC gate running - Ctrl+C to stop")
        dispatchMain()
    }
}
