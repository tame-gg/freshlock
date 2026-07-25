//
//  EndpointSecurityClient.swift
//  FreshLockEnforceExtension
//
//  Defensive Endpoint Security client: AUTH_EXEC allow/deny for locked signing
//  IDs only. No private APIs. Does not run without Apple's managed entitlement
//  on SIP-on systems.
//
//  IMPORTANT: Not embedded in the default FreshLock.app build. Requires
//  Scripts/build-systemextension.sh (+ optional EMBED_SYSTEM_EXTENSION=1) and
//  Apple's com.apple.developer.endpoint-security.client entitlement.
//

import EndpointSecurity
import Foundation
import FreshLockEnforce
import os.log

private let log = Logger(subsystem: "gg.tame.freshlock.enforce", category: "ESClient")

enum ESClientStartError: Error, CustomStringConvertible {
    case notEntitled
    case notPrivileged
    case notPermitted
    case invalidArgument
    case tooManyClients
    case subscribeFailed
    case unknown(es_new_client_result_t)

    var description: String {
        switch self {
        case .notEntitled:
            "Missing com.apple.developer.endpoint-security.client (Apple must grant this)"
        case .notPrivileged:
            "ES client must run as root / in a system extension"
        case .notPermitted:
            "Full Disk Access / TCC not granted for Endpoint Security"
        case .invalidArgument:
            "es_new_client invalid argument"
        case .tooManyClients:
            "Too many ES clients on this Mac"
        case .subscribeFailed:
            "es_subscribe for AUTH_EXEC failed"
        case let .unknown(code):
            "es_new_client failed with code \(code.rawValue)"
        }
    }

    static func from(_ result: es_new_client_result_t) -> ESClientStartError {
        switch result {
        case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED: .notEntitled
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED: .notPrivileged
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED: .notPermitted
        case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT: .invalidArgument
        case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS: .tooManyClients
        default: .unknown(result)
        }
    }
}

/// Thin wrapper around `es_new_client` + `AUTH_EXEC` subscription.
final class EndpointSecurityClient: @unchecked Sendable {
    private var client: OpaquePointer?
    private let lock = NSLock()
    private var evaluator: ExecGateEvaluator
    private let allowlistStore: EnforceAllowlistStore
    private let lockedStore: EnforceLockedSetStore

    init(
        policy: ExecGatePolicy,
        allowlistStore: EnforceAllowlistStore,
        lockedStore: EnforceLockedSetStore
    ) {
        self.allowlistStore = allowlistStore
        self.lockedStore = lockedStore
        let allowlist = (try? allowlistStore.load()) ?? UnlockAllowlist()
        evaluator = ExecGateEvaluator(policy: policy, allowlist: allowlist)
    }

    func reloadAllowlist() {
        reloadFromDisk()
    }

    /// Reload locked signing IDs and unlock allowlist from disk.
    func reloadFromDisk() {
        lock.lock()
        defer { lock.unlock() }
        let allowlist = (try? allowlistStore.load()) ?? UnlockAllowlist()
        let locked = (try? lockedStore.load()) ?? evaluator.policy.lockedSigningIDs
        evaluator.allowlist = allowlist
        evaluator.policy.lockedSigningIDs = locked
    }

    func updatePolicy(_ policy: ExecGatePolicy) {
        lock.lock()
        defer { lock.unlock() }
        evaluator.policy = policy
    }

    func start() throws {
        var newClient: OpaquePointer?
        let result = es_new_client(&newClient) { [weak self] client, message in
            self?.handle(client: client, message: message)
        }

        guard result == ES_NEW_CLIENT_RESULT_SUCCESS, let newClient else {
            throw ESClientStartError.from(result)
        }

        client = newClient

        var events: [es_event_type_t] = [ES_EVENT_TYPE_AUTH_EXEC]
        let sub = es_subscribe(newClient, &events, UInt32(events.count))
        guard sub == ES_RETURN_SUCCESS else {
            es_delete_client(newClient)
            client = nil
            throw ESClientStartError.subscribeFailed
        }

        // Reduce noise from common system helpers (program-path prefix mute).
        _ = es_mute_path(newClient, "/usr/libexec", ES_MUTE_PATH_TYPE_PREFIX)
        _ = es_mute_path(newClient, "/System", ES_MUTE_PATH_TYPE_PREFIX)
        log.info("ES AUTH_EXEC client subscribed")
    }

    func stop() {
        if let client {
            es_unsubscribe_all(client)
            es_delete_client(client)
        }
        client = nil
    }

    deinit {
        stop()
    }

    private func handle(client: OpaquePointer?, message: UnsafePointer<es_message_t>?) {
        guard let client, let message else { return }

        if message.pointee.event_type != ES_EVENT_TYPE_AUTH_EXEC {
            if message.pointee.action_type == ES_ACTION_TYPE_AUTH {
                es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, true)
            }
            return
        }

        let identity = Self.identity(from: message.pointee.event.exec.target)
        lock.lock()
        let decision = evaluator.decision(for: identity)
        let isLocked = evaluator.policy.lockedSigningIDs.contains(identity.signingID)
        lock.unlock()

        let auth: es_auth_result_t = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
        // Cache allows for non-locked binaries; never cache DENY so a later unlock can allow.
        let cache = decision == .allow && !isLocked
        es_respond_auth_result(client, message, auth, cache)

        if decision == .deny {
            log.info("Denied exec signing_id=\(identity.signingID, privacy: .public)")
        }
    }

    private static func identity(from process: UnsafePointer<es_process_t>?) -> ProcessIdentity {
        guard let process else {
            return ProcessIdentity(signingID: "")
        }
        let signingID = stringToken(process.pointee.signing_id) ?? ""
        let teamID = stringToken(process.pointee.team_id)
        let pathToken = process.pointee.executable.pointee.path
        let path = stringToken(pathToken)
        return ProcessIdentity(signingID: signingID, teamID: teamID, executablePath: path)
    }

    private static func stringToken(_ token: es_string_token_t) -> String? {
        guard token.length > 0, let data = token.data else { return nil }
        return String(cString: data)
    }
}
