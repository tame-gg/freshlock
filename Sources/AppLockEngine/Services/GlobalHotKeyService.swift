//
//  GlobalHotKeyService.swift
//  AppLockEngine
//
//  Registers system-wide keyboard shortcuts using Carbon's `RegisterEventHotKey`
//  API. Despite living in the Carbon header, this is a **public, supported** API
//  and the standard way to implement global hot keys on macOS — it works
//  regardless of which app is frontmost and does not require Accessibility.
//
//  We keep a tiny registry keyed by hot-key id so the C event callback (which
//  cannot capture Swift context) can route back to the right closure.
//

import AppLockCore
import Carbon.HIToolbox
import Foundation

/// A registered global hot key handle.
private struct HotKeyEntry {
    let ref: EventHotKeyRef
    let handler: () -> Void
}

/// Registers and dispatches global keyboard shortcuts.
@MainActor
public final class GlobalHotKeyService {
    /// Shared instance so the nonisolated C callback has a stable route home.
    static let shared = GlobalHotKeyService()

    private var entries: [UInt32: HotKeyEntry] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    /// FourCC signature identifying our hot keys.
    private let signature: OSType = 0x414C_4B48 // 'ALKH'

    public init() {}

    /// Install the single application-level Carbon event handler (idempotent).
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The callback is a bare C function pointer (no captures), so it routes
        // through the shared singleton. Carbon delivers on the main thread.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr else { return status }
            let id = hkID.id
            MainActor.assumeIsolated {
                GlobalHotKeyService.shared.dispatch(id: id)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    private func dispatch(id: UInt32) {
        entries[id]?.handler()
    }

    /// Register a shortcut. Returns an opaque id, or `nil` if registration
    /// failed (e.g. the combo is already claimed system-wide).
    @discardableResult
    public func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) -> UInt32? {
        guard shortcut.isValid else { return nil }
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: signature, id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.general.error("Failed to register hot key (status \(status))")
            return nil
        }
        entries[id] = HotKeyEntry(ref: ref, handler: handler)
        return id
    }

    /// Unregister a previously-registered shortcut by id.
    public func unregister(_ id: UInt32) {
        guard let entry = entries[id] else { return }
        UnregisterEventHotKey(entry.ref)
        entries[id] = nil
    }

    /// Unregister everything (used when reloading shortcuts).
    public func unregisterAll() {
        for (_, entry) in entries {
            UnregisterEventHotKey(entry.ref)
        }
        entries.removeAll()
    }

    /// Translate our portable modifier set into Carbon modifier flags.
    private static func carbonModifiers(_ mods: GlobalShortcut.ModifierSet) -> UInt32 {
        var carbon: UInt32 = 0
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        if mods.contains(.option) { carbon |= UInt32(optionKey) }
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        if mods.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
