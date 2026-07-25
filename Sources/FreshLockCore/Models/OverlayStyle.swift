//
//  OverlayStyle.swift
//  FreshLockCore
//
//  Presentation options for the lock overlay. Kept in the core so that both
//  settings persistence and the (UI-side) renderer agree on the vocabulary.
//

import Foundation

/// Visual treatment applied to the lock overlay window. Deliberately limited to
/// polished, native-feeling looks (the old "minimal" scrim was removed).
public enum OverlayStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// A translucent `NSVisualEffectView` blur over the covered content.
    case blur

    /// A solid, opaque background using the current appearance's window colour.
    case solid

    public var displayName: String {
        switch self {
        case .blur: "Blurred"
        case .solid: "Solid"
        }
    }

    public static let `default`: OverlayStyle = .blur

    /// Decode leniently: an unknown value (e.g. the removed "minimal" from an
    /// older configuration) falls back to the default rather than failing the
    /// whole document.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OverlayStyle(rawValue: raw) ?? .default
    }
}
