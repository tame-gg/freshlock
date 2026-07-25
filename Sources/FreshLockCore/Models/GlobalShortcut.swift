//
//  GlobalShortcut.swift
//  FreshLockCore
//
//  A framework-free representation of a system-wide keyboard shortcut. It stores
//  a virtual key code (matching `NSEvent.keyCode` / `kVK_*`) and a portable set
//  of modifier flags. The engine translates this into a Carbon hot key; the UI
//  translates it into a glyph string. Keeping it Carbon/AppKit-free lets it live
//  in the core and be persisted inside `AppSettings`.
//

import Foundation

/// A user-assigned global shortcut.
public struct GlobalShortcut: Codable, Hashable, Sendable {
    /// Virtual key code, as delivered by `NSEvent.keyCode`.
    public var keyCode: UInt16

    /// The modifier keys that must be held.
    public var modifiers: ModifierSet

    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A portable modifier flag set, independent of AppKit's `NSEvent` and
    /// Carbon's flag constants.
    public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = ModifierSet(rawValue: 1 << 0)
        public static let option = ModifierSet(rawValue: 1 << 1)
        public static let shift = ModifierSet(rawValue: 1 << 2)
        public static let command = ModifierSet(rawValue: 1 << 3)
    }

    /// A shortcut is only usable if it carries at least one non-shift modifier —
    /// bare or shift-only keys would fire during ordinary typing.
    public var isValid: Bool {
        modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
    }
}
