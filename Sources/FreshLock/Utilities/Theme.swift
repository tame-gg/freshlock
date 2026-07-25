//
//  Theme.swift
//  FreshLock
//
//  Fluent native macOS visual language: system materials, semantic label colors,
//  and a quiet brand accent. Avoids custom navy canvases and cyan→green
//  marketing gradients so Liquid Glass / system chrome can read correctly.
//

import AppKit
import SwiftUI

enum Theme {
    /// Quiet lock-adjacent accent; desaturated enough to sit with system chrome.
    static let accent = Color(nsColor: .systemTeal)

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

    /// Standard continuous corner used for inset surfaces.
    static let cornerRadius: CGFloat = 10
}

extension EnvironmentValues {
    @Entry var preferLiquidGlass: Bool = true
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
