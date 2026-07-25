//
//  GracePeriodPreset.swift
//  FreshLockCore
//
//  Named grace-period durations for Preferences and onboarding. Persistence is
//  always `gracePeriodSeconds` (Int); presets and custom unit UI convert to/from
//  that single stored value.
//

import Foundation

/// Built-in grace period choices offered in the UI.
public enum GracePeriodPreset: Int, CaseIterable, Hashable, Sendable, Codable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    /// Seconds this preset stores in `AppSettings.gracePeriodSeconds`.
    public var seconds: Int {
        rawValue
    }

    /// Short label for pickers ("15s", "1m", …).
    public var displayName: String {
        switch self {
        case .fifteenSeconds: "15s"
        case .thirtySeconds: "30s"
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        case .fifteenMinutes: "15m"
        }
    }

    /// The preset that exactly matches `seconds`, if any.
    public static func matching(_ seconds: Int) -> GracePeriodPreset? {
        allCases.first { $0.seconds == seconds }
    }
}

/// Display unit for the Custom grace-period editor. Converted to seconds on save.
public enum GracePeriodUnit: String, CaseIterable, Hashable, Sendable {
    case seconds
    case minutes
    case hours

    public var displayName: String {
        switch self {
        case .seconds: "Seconds"
        case .minutes: "Minutes"
        case .hours: "Hours"
        }
    }

    /// Convert a positive display quantity into whole seconds.
    public func toSeconds(_ value: Int) -> Int {
        let clamped = max(0, value)
        switch self {
        case .seconds: return clamped
        case .minutes: return clamped * 60
        case .hours: return clamped * 3600
        }
    }

    /// Best unit + quantity for editing an arbitrary second count in Custom mode.
    /// Prefers the largest unit that divides evenly (hours, then minutes).
    public static func preferredDisplay(forSeconds seconds: Int) -> (value: Int, unit: GracePeriodUnit) {
        let total = max(0, seconds)
        if total > 0, total % 3600 == 0 {
            return (total / 3600, .hours)
        }
        if total > 0, total % 60 == 0 {
            return (total / 60, .minutes)
        }
        return (total, .seconds)
    }
}

public extension GracePeriodUnit {
    /// Inclusive upper bound for the Custom stepper, per unit.
    var maxValue: Int {
        switch self {
        case .seconds: 86400 // 24h
        case .minutes: 1440 // 24h
        case .hours: 24
        }
    }
}
