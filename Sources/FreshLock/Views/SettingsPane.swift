//
//  SettingsPane.swift
//  FreshLock
//
//  Settings is split into pages instead of one long scrolling Form. Each page is
//  a sidebar row (icon + name) and a detail pane introduced by a one-line
//  summary, the way System Settings organises preferences.
//
//  Iconography is SF Symbols, bare - no tinted tiles behind them. Symbols are
//  drawn hierarchically in the secondary label colour so they read as a quiet
//  aligned column rather than a row of saturated badges.
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
        case .general: "gearshape"
        case .locking: "lock.rotation"
        case .shortcuts: "command"
        case .backup: "arrow.up.arrow.down"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }

    /// Plain-language line shown above the page. It replaces the preamble
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

// MARK: - Page chrome

/// The summary strip above a settings page. Uses the same `.bar` material and
/// divider as the sidebar footer so window chrome stays one system.
struct SettingsPageHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(spacing: 0) {
            Text(pane.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            Divider()
        }
        .background(.bar)
    }
}

// MARK: - Row label

/// Icon + title + optional explanatory line, for the primary control of a
/// settings group. Secondary controls stay as plain text rows so the icon
/// column marks what matters instead of decorating every line.
struct SettingsRowLabel: View {
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .frame(width: Theme.settingsIconColumn, alignment: .center)
                .accessibilityHidden(true)

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

/// A caption that lines up with `SettingsRowLabel` text rather than the icon,
/// for the follow-up notes that only appear in certain states.
struct SettingsRowNote: View {
    let text: LocalizedStringKey
    var isError = false

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Theme.settingsIconColumn + 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
