//
//  InstalledApp+Icon.swift
//  FreshLock
//
//  Bridges the framework-free `InstalledApp` model to an AppKit icon. This
//  lives in the app target (not the core library) precisely because it pulls in
//  AppKit, which we keep out of `FreshLockCore`.
//

import AppKit
import FreshLockCore
import SwiftUI

extension InstalledApp {
    /// The Finder icon for this bundle, resolved lazily from disk. Falls back to
    /// a generic application icon if the bundle can't be read.
    var icon: NSImage {
        let workspace = NSWorkspace.shared
        if FileManager.default.fileExists(atPath: path) {
            return workspace.icon(forFile: path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    /// SwiftUI-ready image.
    var iconImage: Image {
        Image(nsImage: icon)
    }
}
