//
//  Theme.swift
//  FreshLock
//
//  Native macOS utility chrome: system materials, semantic colors, and a quiet
//  system accent for controls. Brand teal is reserved for the FreshLock mark
//  only - never loud segmented fills or row outlines.
//

import AppKit
import SwiftUI

enum Theme {
    /// System control accent (typically restrained blue) for toggles, selection, icons.
    static let accent = Color.accentColor

    /// Subtle lock-adjacent brand teal for the app mark fallback only.
    static let brand = Color(nsColor: .systemTeal)

    /// Protected / success emphasis (tonal, not neon).
    static let protected = Color(nsColor: .systemGreen)

    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var separator: Color {
        Color(nsColor: .separatorColor)
    }

    /// Continuous corner used for inset grouped surfaces.
    static let cornerRadius: CGFloat = 10

    /// Sidebar column ideal width (BetterDisplay-style utility).
    static let sidebarWidth: CGFloat = 180
}

private enum PreferLiquidGlassKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var preferLiquidGlass: Bool {
        get { self[PreferLiquidGlassKey.self] }
        set { self[PreferLiquidGlassKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
