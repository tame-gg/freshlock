//
//  ProtectedAppProcess.swift
//  FreshLockEngine
//
//  Resolves the *live process* for a protected app. Bundle identifier is the
//  persistent identity used everywhere for membership (protected list, overlay,
//  unlock store keys, events). PID is only a session token for "this launch".
//
//  When multiple processes share a bundle ID (quit/relaunch overlap), prefer:
//  1. The frontmost instance of that bundle
//  2. Otherwise the most recently launched non-terminated instance
//  Never use `.first` — its order is undefined and caused wrong-PID grants.
//

import AppKit
import Foundation

enum ProtectedAppProcess {
    /// Best live `NSRunningApplication` for `bundleID`, or `nil` if none.
    static func running(bundleID: String) -> NSRunningApplication? {
        let apps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        guard !apps.isEmpty else { return nil }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier == bundleID,
           !front.isTerminated
        {
            return front
        }

        return apps.sorted {
            ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast)
        }.first
    }

    static func pid(forBundleID bundleID: String) -> pid_t? {
        running(bundleID: bundleID)?.processIdentifier
    }

    /// All live PIDs for a bundle (for dead-session checks).
    static func allPIDs(forBundleID bundleID: String) -> Set<pid_t> {
        Set(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated }
                .map(\.processIdentifier)
        )
    }

    /// Map of bundleID → live PID set for every enabled protected app.
    ///
    /// Uses a single `runningApplications` snapshot instead of one Launch
    /// Services query per bundle — this runs on the liveness poll, so its cost
    /// must not scale with the size of the protected list.
    static func livePIDSets(forBundleIDs bundleIDs: [String]) -> [String: Set<pid_t>] {
        guard !bundleIDs.isEmpty else { return [:] }
        let wanted = Set(bundleIDs)
        var result: [String: Set<pid_t>] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard let id = app.bundleIdentifier, wanted.contains(id) else { continue }
            result[id, default: []].insert(app.processIdentifier)
        }
        return result
    }
}
