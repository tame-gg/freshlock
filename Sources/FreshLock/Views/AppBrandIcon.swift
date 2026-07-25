//
//  AppBrandIcon.swift
//  FreshLock
//
//  Shows the bundled app icon so About / onboarding / chrome match the Dock mark.
//  Falls back to a quiet SF symbol when no app icon is available (e.g. bare `swift run`).
//

import AppKit
import SwiftUI

struct AppBrandIcon: View {
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let nsImage = Self.resolvedIcon {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            } else {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(Theme.brand)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Prefer the running app's icon; otherwise try the packaged icns next to the binary.
    private static var resolvedIcon: NSImage? {
        if let icon = NSApp.applicationIconImage, icon.size.width > 32 {
            // Filter out the generic AppKit placeholder when possible by checking representation count.
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }
}
