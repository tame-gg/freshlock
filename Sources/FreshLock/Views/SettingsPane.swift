//
//  SettingsPane.swift
//  FreshLock
//
//  Settings is split into pages instead of one long scrolling form. Each page
//  is a sidebar row and a detail pane, so no page is longer than a screen.
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

    var id: String {
        rawValue
    }

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
        case .backup: "externaldrive.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info"
        }
    }

    /// Plain-language line under the page title, in place of the preamble
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
