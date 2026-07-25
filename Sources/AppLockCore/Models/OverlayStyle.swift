//
//  OverlayStyle.swift
//  AppLockCore
//
//  Presentation options for the lock overlay. Kept in the core so that both
//  settings persistence and the (UI-side) renderer agree on the vocabulary.
//

import Foundation

/// Visual treatment applied to the lock overlay window.
public enum OverlayStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// A translucent `NSVisualEffectView` blur over the covered content.
    case blur

    /// A solid, opaque background using the current appearance's window colour.
    case solid

    /// A minimal, mostly-transparent scrim with just the auth prompt.
    case minimal

    public var displayName: String {
        switch self {
        case .blur: "Blurred"
        case .solid: "Solid"
        case .minimal: "Minimal"
        }
    }

    public static let `default`: OverlayStyle = .blur
}
