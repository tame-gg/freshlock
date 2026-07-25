//
//  SettingsPane.swift
//  FreshLock
//
//  Settings is split into pages instead of one long scrolling Form. Each page is
//  a sidebar row and a detail pane, the way System Settings organises
//  preferences on modern macOS.
//
//  Iconography follows the current system look: an SF Symbol in a tinted,
//  gradient-filled rounded square. The same tile is reused in the sidebar and at
//  the head of each settings row so the two read as one system.
//

import SwiftUI

/// One page of Settings.
enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general
    case locking
    case shortcuts
    case backup
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .locking: "Locking"
        case .shortcuts: "Shortcuts"
        case .backup: "Backup"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .locking: "lock.rotation"
        case .shortcuts: "command"
        case .backup: "arrow.up.arrow.down"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: Theme.tileGray
        case .locking: Theme.tileBlue
        case .shortcuts: Theme.tileIndigo
        case .backup: Theme.tileTeal
        case .advanced: Theme.tileOrange
        case .about: Theme.tilePink
        }
    }

    /// Plain-language line under the page title. Replaces the preamble
    /// paragraphs that used to sit inside the form itself.
    var summary: String {
        switch self {
        case .general: "Startup, menu bar, and how a locked app looks."
        case .locking: "When FreshLock asks for Touch ID again."
        case .shortcuts: "Global keys for locking and unlocking everything."
        case .backup: "Move protected apps and preferences between Macs."
        case .advanced: "Permissions, developer tools, and the setup guide."
        case .about: "Version, credits, and project links."
        }
    }
}

// MARK: - Icon tile

/// The system-style settings glyph: a white SF Symbol on a tinted, softly
/// graded rounded square.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var side: CGFloat = Theme.tileSideSidebar

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(tint.gradient)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Page chrome

/// Bold page title and summary above a settings page, matching the weight of
/// the toolbar title on the library pages and closing with the same hairline.
struct SettingsPageHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: pane.symbolName, tint: pane.tint, side: Theme.tileSideHeader)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                        .font(.headline)
                    Text(pane.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
        }
        .background(.bar)
    }
}

// MARK: - Row label

/// Tile + title + optional explanatory line, for the primary control of a
/// settings group.
struct SettingsRowLabel: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, side: Theme.tileSideRow)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A caption aligned to `SettingsRowLabel` text rather than its tile, for the
/// follow-up notes that only appear in certain states.
struct SettingsRowNote: View {
    let text: LocalizedStringKey
    var isError = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Theme.tileSideRow + 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
