//
//  GlobalShortcutTests.swift
//  FreshLockCoreTests
//

import Testing
import Foundation
@testable import FreshLockCore

struct GlobalShortcutTests {
    @Test func validityRequiresNonShiftModifier() {
        // ⌘L is valid.
        #expect(GlobalShortcut(keyCode: 37, modifiers: [.command]).isValid)
        // ⇧L alone is not (would fire while typing).
        #expect(GlobalShortcut(keyCode: 37, modifiers: [.shift]).isValid == false)
        // No modifiers is not valid.
        #expect(GlobalShortcut(keyCode: 37, modifiers: []).isValid == false)
        // ⌃⌥ combos are valid.
        #expect(GlobalShortcut(keyCode: 37, modifiers: [.control, .option]).isValid)
    }

    @Test func roundTripsInSettings() throws {
        var settings = AppSettings()
        settings.lockAllShortcut = GlobalShortcut(keyCode: 37, modifiers: [.command, .option])
        settings.unlockAllShortcut = GlobalShortcut(keyCode: 49, modifiers: [.control])

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.lockAllShortcut?.modifiers.contains(.command) == true)
    }

    @Test func modifierSetIsAnOptionSet() {
        var mods: GlobalShortcut.ModifierSet = [.command]
        mods.insert(.shift)
        #expect(mods.contains(.command))
        #expect(mods.contains(.shift))
        #expect(!mods.contains(.control))
    }
}
