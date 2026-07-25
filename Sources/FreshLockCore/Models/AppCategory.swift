//
//  AppCategory.swift
//  FreshLockCore
//
//  A lightweight, user-assignable grouping for protected apps. Categories are
//  purely organisational (they drive the sidebar) and never affect security.
//

import Foundation

/// A user-facing grouping shown in the sidebar.
///
/// The built-in cases mirror the sort of buckets Apple uses in the App Store,
/// plus an `.other` catch-all. `custom` lets power users define their own.
public enum AppCategory: Codable, Hashable, Sendable, CaseIterable {
    case social
    case finance
    case productivity
    case developer
    case system
    case entertainment
    case other

    public static var allCases: [AppCategory] {
        [.social, .finance, .productivity, .developer, .system, .entertainment, .other]
    }

    /// SF Symbol used to represent the category in the sidebar.
    public var symbolName: String {
        switch self {
        case .social: "person.2.fill"
        case .finance: "creditcard.fill"
        case .productivity: "checkmark.circle.fill"
        case .developer: "hammer.fill"
        case .system: "gearshape.fill"
        case .entertainment: "play.tv.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// Human-readable, English display name. UI layers should localise this.
    public var displayName: String {
        switch self {
        case .social: "Social"
        case .finance: "Finance"
        case .productivity: "Productivity"
        case .developer: "Developer"
        case .system: "System"
        case .entertainment: "Entertainment"
        case .other: "Other"
        }
    }
}
