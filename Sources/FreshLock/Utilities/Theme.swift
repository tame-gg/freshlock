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

    // MARK: Icon wells

    //
    // Every navigable destination gets the same soft brand-tinted well with a
    // dark glyph. One tone across the whole column reads as a considered set;
    // a different hue per row reads as noise.

    static let wellFill = dynamic(
        light: NSColor(srgbRed: 0.725, green: 0.847, blue: 0.808, alpha: 1),
        dark: NSColor(srgbRed: 0.784, green: 0.886, blue: 0.851, alpha: 1)
    )

    static let wellGlyph = Color(hex: 0x13332B)

    /// Well side in the sidebar and at the head of a page.
    static let wellSideSidebar: CGFloat = 24
    static let wellSidePage: CGFloat = 30

    // MARK: Grouped cards

    //
    // Settings rows live on soft raised islands rather than one merged table,
    // so a page can be scanned by shape before it is read.

    static let cardFill = dynamic(
        light: NSColor(white: 1, alpha: 0.92),
        dark: NSColor(white: 1, alpha: 0.055)
    )

    static let cardStroke = dynamic(
        light: NSColor(white: 0, alpha: 0.07),
        dark: NSColor(white: 1, alpha: 0.07)
    )

    /// Quiet neutral selection, so the wells stay the only colour in the sidebar.
    static let sidebarSelection = dynamic(
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.14)
    )

    static let cardCornerRadius: CGFloat = 12

    /// Point size for app icons in the menu-bar menu (matches the menu text).
    static let menuAppIconSize: CGFloat = 16

    /// Point size for SF Symbols used as menu-item images.
    static let menuSymbolSize: CGFloat = 13

    /// A colour that resolves per appearance, so one constant covers both modes.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
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
