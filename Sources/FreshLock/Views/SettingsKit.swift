//
//  SettingsKit.swift
//  FreshLock
//
//  The shared visual language for the main window: soft tonal icon wells, page
//  headers, and grouped "island" cards.
//
//  Settings deliberately does not use SwiftUI's grouped `Form`. A Form gives one
//  merged table with fixed metrics; these pieces give roomier rows, larger
//  corner radii, and the option to float a single control on its own island,
//  which is what makes a settings page feel current rather than like a
//  system-preferences pane from a decade ago.
//

import SwiftUI

// MARK: - Icon well

/// A rounded, brand-tinted square holding a dark glyph. Used for every sidebar
/// destination and at the head of every page, at two sizes.
struct IconWell: View {
    let symbol: String
    var side: CGFloat = Theme.wellSideSidebar
    var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(Theme.wellFill)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.5, weight: .semibold))
                    .foregroundStyle(Theme.wellGlyph)
            }
            .opacity(isDimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Page header

/// Well, title, and one line of context, above a hairline. Every detail pane
/// uses this - library pages and settings pages alike - so switching between
/// them never changes the shape of the window.
struct PageHeader: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconWell(symbol: symbol, side: Theme.wellSidePage)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            Divider()
        }
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page body

/// Scrolling column for a settings page: generous gutters, capped measure so
/// long descriptions stay readable on a wide window.
struct SettingsPageBody<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // A checkbox is the AppKit default outside a Form, and a page of
        // checkboxes reads as a decade-old preferences pane. Every on/off
        // control here is a switch.
        .toggleStyle(.switch)
    }
}

// MARK: - Section

/// A bold group title with its cards underneath. The title sits on the page
/// background rather than inside the card, the way Finder and Canopy group
/// controls.
struct SettingsSection<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .padding(.leading, 4)
            }
            content
        }
    }
}

/// Explanatory line under a card, aligned with the card's inner text.
struct SettingsFootnote: View {
    let text: LocalizedStringKey
    var isError = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card

/// A soft raised island. One row on its own, or several separated by
/// `CardDivider`.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        )
    }
}

/// Hairline between rows of one card, inset past the glyph column.
struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, SettingsRowMetrics.textInset)
    }
}

enum SettingsRowMetrics {
    static let glyphColumn: CGFloat = 20
    static let spacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    /// Left edge of a row's text, for aligning dividers and continuation content.
    static var textInset: CGFloat {
        horizontalPadding + glyphColumn + spacing
    }
}

// MARK: - Row

/// Glyph, title, optional description, and a trailing control.
struct SettingsRow<Control: View>: View {
    let symbol: String?
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: SettingsRowMetrics.spacing) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsRowMetrics.glyphColumn)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
        .padding(.vertical, 11)
    }
}

extension SettingsRow where Control == EmptyView {
    init(symbol: String?, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A row that is entirely a button, for actions like export and import.
struct SettingsActionRow: View {
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(symbol: symbol, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Content that continues a row inside the same card - a stepper that only
/// applies to the choice above it, or a wrapped block of detail.
struct CardContinuation<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
        .padding(.leading, SettingsRowMetrics.textInset)
        .padding(.trailing, SettingsRowMetrics.horizontalPadding)
        .padding(.bottom, 12)
    }
}
