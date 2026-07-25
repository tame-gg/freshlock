//
//  RelockPolicyEditing.swift
//  FreshLock
//
//  UI-side helpers that make the associated-value `RelockPolicy` enum editable
//  with a simple `Picker` + `Stepper`. `PolicyKind` is the flat, hashable set of
//  choices the picker offers (including "use the global default"); it converts
//  to/from the richer model type.
//

import FreshLockCore

extension RelockPolicy {
    /// A short, human-readable label for the policy, used in the editor and to
    /// describe the inherited default.
    var editorLabel: String {
        switch self {
        case .everyLaunch: "Once per launch"
        case .afterMinutes(let m): "After \(m) min"
        case .afterSleep: "After sleep"
        case .afterScreenLock: "After screen lock"
        case .afterInactivity(let m): "After \(m) min idle"
        case .afterSwitchingAway: "When switching away"
        case .manualOnly: "Manual only"
        }
    }
}

/// The flat set of choices shown in the relock picker.
enum PolicyKind: Hashable, CaseIterable {
    case useDefault
    case everyLaunch
    case afterMinutes
    case afterSleep
    case afterScreenLock
    case afterInactivity
    case afterSwitchingAway
    case manualOnly

    /// All choices except "use default", for listing after the default row.
    static var explicitCases: [PolicyKind] {
        allCases.filter { $0 != .useDefault }
    }

    /// Whether this choice needs an accompanying minutes value.
    var needsMinutes: Bool {
        self == .afterMinutes || self == .afterInactivity
    }

    var displayName: String {
        switch self {
        case .useDefault: "Default"
        case .everyLaunch: "Once per launch"
        case .afterMinutes: "After N minutes"
        case .afterSleep: "After sleep"
        case .afterScreenLock: "After screen lock"
        case .afterInactivity: "After inactivity"
        case .afterSwitchingAway: "When switching away"
        case .manualOnly: "Manual only"
        }
    }

    /// Derive the picker choice from a stored (optional) policy. `nil` → default.
    init(from policy: RelockPolicy?) {
        switch policy {
        case .none: self = .useDefault
        case .everyLaunch: self = .everyLaunch
        case .afterMinutes: self = .afterMinutes
        case .afterSleep: self = .afterSleep
        case .afterScreenLock: self = .afterScreenLock
        case .afterInactivity: self = .afterInactivity
        case .afterSwitchingAway: self = .afterSwitchingAway
        case .manualOnly: self = .manualOnly
        }
    }

    /// Build the model policy for this choice. `useDefault` maps to `nil`, which
    /// the model interprets as "inherit the global default".
    func makePolicy(minutes: Int) -> RelockPolicy? {
        switch self {
        case .useDefault: nil
        case .everyLaunch: .everyLaunch
        case .afterMinutes: .afterMinutes(minutes)
        case .afterSleep: .afterSleep
        case .afterScreenLock: .afterScreenLock
        case .afterInactivity: .afterInactivity(minutes)
        case .afterSwitchingAway: .afterSwitchingAway
        case .manualOnly: .manualOnly
        }
    }
}
