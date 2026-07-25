//
//  Theme.swift
//  AppLock
//
//  The visual language, inspired by koels.net: a deep navy canvas with a soft
//  teal glow, big bold headings with a cyan→green gradient, bright-blue rounded
//  accents, and small uppercase tracked micro-labels. Centralising it here keeps
//  the redesigned views consistent.
//

import SwiftUI

enum Theme {
    // MARK: Canvas
    static let base = Color(hex: 0x0B0F17)
    static let baseElevated = Color(hex: 0x0E131E)
    static let card = Color(hex: 0x141A26)
    static let cardHover = Color(hex: 0x18202F)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.12)

    // MARK: Text
    static let textPrimary = Color(hex: 0xE7ECF5)
    static let textSecondary = Color(hex: 0x9AA5B6)
    static let textMuted = Color(hex: 0x5E6a7c)

    // MARK: Accent
    static let accent = Color(hex: 0x5AA9FF)
    static let cyan = Color(hex: 0x7DE3FF)
    static let green = Color(hex: 0x6EE7B7)

    /// The signature cyan→green wordmark gradient.
    static let brandGradient = LinearGradient(
        colors: [cyan, green],
        startPoint: .leading, endPoint: .trailing
    )

    /// The page background: navy with a subtle teal radial glow, koels-style.
    static var background: some View {
        ZStack {
            base
            RadialGradient(
                colors: [green.opacity(0.10), .clear],
                center: .init(x: 0.35, y: 0.9), startRadius: 20, endRadius: 620
            )
            RadialGradient(
                colors: [accent.opacity(0.08), .clear],
                center: .init(x: 0.9, y: 0.05), startRadius: 20, endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}

/// A small uppercase, letter-spaced label with a leading dash — the koels.net
/// section marker ("— APP PROTECTION").
struct MicroLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Theme.textMuted)
                .frame(width: 18, height: 1)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.textMuted)
        }
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
