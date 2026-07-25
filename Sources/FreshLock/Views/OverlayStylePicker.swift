//
//  OverlayStylePicker.swift
//  FreshLock
//
//  A choice between two looks is better shown than named, so each option is a
//  tile rendering the effect it selects: the blurred option really is a blur
//  over content, the solid one really is the window fill. A pop-up menu of the
//  words "Blurred" and "Solid" made the user open Settings, pick one, and go
//  look at a locked app to find out what they had chosen.
//

import FreshLockCore
import SwiftUI

struct OverlayStylePicker: View {
    @Binding var selection: OverlayStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(OverlayStyle.allCases, id: \.self) { style in
                tile(for: style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(for style: OverlayStyle) -> some View {
        let isSelected = selection == style
        return Button {
            selection = style
        } label: {
            VStack(spacing: 7) {
                preview(for: style)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(style.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.sidebarSelection : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.wellGlyph.opacity(0.55) : Theme.cardStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A miniature of what the lock cover will look like: sample content with
    /// the chosen treatment over it, plus the padlock the real overlay shows.
    private func preview(for style: OverlayStyle) -> some View {
        ZStack {
            switch style {
            case .blur:
                // A real blur radius, not a material: a material samples what is
                // behind the *window*, so over a sibling view it flattens into a
                // wash and the tile stops looking like a blur at all.
                sampleContent
                    .blur(radius: 7)
                    .overlay(Rectangle().fill(Color.white.opacity(0.18)))
            case .solid:
                sampleContent
                    .overlay(Rectangle().fill(Theme.windowBackground))
            }
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style == .blur ? .white : .secondary)
        }
        .clipped()
    }

    private var sampleContent: some View {
        LinearGradient(
            colors: [Theme.brand.opacity(0.85), Theme.accent.opacity(0.7), Theme.brand.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.white.opacity(0.55)).frame(width: 34, height: 4)
                Capsule().fill(.white.opacity(0.4)).frame(width: 52, height: 4)
                Capsule().fill(.white.opacity(0.4)).frame(width: 26, height: 4)
            }
            .padding(8)
        }
    }
}
