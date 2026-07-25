//
//  LiquidGlass.swift
//  FreshLock
//
//  Liquid Glass support for FreshLock chrome.
//
//  ## Research notes (WWDC 2025 / 2026, macOS 26–27)
//
//  - Liquid Glass shipped as the system design language in macOS 26 (Tahoe) via
//    SwiftUI `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
//    and AppKit `NSGlassEffectView` / `NSGlassEffectContainerView`.
//  - macOS 27 refines the material and adds a **system** Appearance slider
//    (ultra clear ↔ fully tinted). Standard SwiftUI glass automatically follows
//    that slider; apps do not reimplement intensity.
//  - There is no public per-app API to disable system Liquid Glass chrome.
//    `UIDesignRequiresCompatibility` was a temporary opt-out for apps built
//    against the macOS 26 SDK and is **ignored** when linking the macOS 27 SDK.
//  - FreshLock's user toggle therefore controls whether *our* surfaces opt into
//    `.glassEffect` (macOS 26+) vs classic `.regularMaterial` / solid fills.
//    On macOS 15–25 the toggle is stored but glass APIs are unavailable, so
//    materials are used. On macOS 27, leaving glass on also respects the
//    system Appearance tint slider automatically.
//
//  Availability: glass APIs are `@available(macOS 26.0, *)`. Interactive glass
//  (`Glass.interactive()` / `NSGlassEffectView.effectIsInteractive`) is refined
//  further on macOS 27.
//

import SwiftUI

enum LiquidGlassSupport {
    /// Runtime check: glass APIs exist on this OS.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    /// Short footnote for Preferences.
    static var availabilityNote: String {
        if isAvailable {
            "Glass surfaces follow System Settings → Appearance on macOS 27."
        } else {
            "Requires macOS 26 or later. Your preference is saved for when you upgrade."
        }
    }
}

extension View {
    /// Applies Liquid Glass when preferred and available; otherwise a system material.
    @ViewBuilder
    func freshLockGlass(
        enabled: Bool,
        in shape: some Shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous),
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *), enabled {
            // `.interactive()` adds pointer-responsive glass on macOS 26+;
            // macOS 27 further tunes this for mouse (see NSGlassEffectView).
            let glass = interactive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Toolbar / header cluster wrapped so sibling glass shapes can morph.
    @ViewBuilder
    func freshLockGlassContainer<Content: View>(
        enabled: Bool,
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *), enabled {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
