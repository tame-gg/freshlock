//
//  AuthPromptBudget.swift
//  FreshLockEngine
//
//  Rate limit for *automatic* Touch ID prompts, plus the record of which sheet
//  is currently on screen.
//
//  Without a budget, any outcome that is neither success nor an explicit user
//  cancel leaves the app frontmost, locked, and covered - exactly the condition
//  the liveness poll re-secures - so FreshLock raises a new sheet every 1.5s and
//  steals focus each time. That is what made the protected app, FreshLock, and
//  the sheet itself all unclickable.
//

import Foundation

struct AuthPromptBudget {
    /// Automatic prompts allowed per app inside `window` before FreshLock stops
    /// asking and waits for the overlay's Unlock button.
    static let maxAutomaticPrompts = 3
    static let window: TimeInterval = 12
    /// A sheet younger than this is assumed to be settling, not being dismissed
    /// by a real app switch: raising it bounces focus on its own.
    static let cancelGrace: TimeInterval = 1.5

    private var recentPrompts: [String: [Date]] = [:]
    private var presentingFor: String?
    private var presentedAt: Date?

    /// The app whose Touch ID sheet is believed to be on screen.
    var presentingBundleID: String? {
        presentingFor
    }

    mutating func reset() {
        recentPrompts.removeAll()
        presentingFor = nil
        presentedAt = nil
    }

    mutating func clearHistory(for bundleID: String) {
        recentPrompts[bundleID] = nil
    }

    mutating func recordPresented(_ bundleID: String, at date: Date = Date()) {
        presentingFor = bundleID
        presentedAt = date
    }

    mutating func clearPresented(for bundleID: String) {
        guard presentingFor == bundleID else { return }
        presentingFor = nil
        presentedAt = nil
    }

    /// True while `bundleID`'s sheet is too young to be torn down by a focus
    /// change.
    func isWithinCancelGrace(_ bundleID: String, now: Date = Date()) -> Bool {
        guard presentingFor == bundleID, let presentedAt else { return false }
        return now.timeIntervalSince(presentedAt) < Self.cancelGrace
    }

    /// Record an automatic prompt and report whether it is still within budget.
    mutating func allowAutomaticPrompt(for bundleID: String, now: Date = Date()) -> Bool {
        var stamps = (recentPrompts[bundleID] ?? [])
            .filter { now.timeIntervalSince($0) < Self.window }
        guard stamps.count < Self.maxAutomaticPrompts else {
            recentPrompts[bundleID] = stamps
            return false
        }
        stamps.append(now)
        recentPrompts[bundleID] = stamps
        return true
    }

    /// Whether another prompt would be allowed, without spending the budget.
    func hasBudget(for bundleID: String, now: Date = Date()) -> Bool {
        let stamps = (recentPrompts[bundleID] ?? [])
            .filter { now.timeIntervalSince($0) < Self.window }
        return stamps.count < Self.maxAutomaticPrompts
    }
}
