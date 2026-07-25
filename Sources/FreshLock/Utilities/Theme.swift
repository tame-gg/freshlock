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

    /// Width reserved for the leading symbol in a settings row, so icons and the
    /// notes underneath them share one alignment column.
    static let settingsIconColumn: CGFloat = 18

    /// Point size for app icons in the menu-bar menu (matches the menu text).
    static let menuAppIconSize: CGFloat = 16

    /// Point size for SF Symbols used as menu-item images.
    static let menuSymbolSize: CGFloat = 13
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
