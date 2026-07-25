//
//  ShortcutRecorderView.swift
//  FreshLock
//
//  A small control for capturing a global keyboard shortcut. Clicking it enters
//  "recording" mode; the next modified key-down is captured as a `GlobalShortcut`.
//  Escape cancels, Delete/Backspace (with no modifiers) clears the shortcut.
//
//  It is implemented as an `NSViewRepresentable` wrapping a focusable `NSView`,
//  because reliably capturing a raw key-down with modifiers is an AppKit
//  responder-chain concern that SwiftUI doesn't expose directly.
//

import AppKit
import FreshLockCore
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut?

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = { shortcut = $0 }
        view.onClear = { shortcut = nil }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.shortcut = shortcut
        nsView.needsDisplay = true
    }
}

/// The focusable AppKit view that does the capturing and draws the current state.
final class RecorderNSView: NSView {
    var shortcut: GlobalShortcut?
    var onCapture: ((GlobalShortcut) -> Void)?
    var onClear: (() -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 24) }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels; bare Delete clears.
        if event.keyCode == 53 { // Escape
            isRecording = false
            return
        }
        if event.keyCode == 51, event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
            onClear?()
            isRecording = false
            return
        }

        if let captured = GlobalShortcut(event: event) {
            onCapture?(captured)
            isRecording = false
        } else {
            NSSound.beep() // needs at least one non-shift modifier
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 5
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String = isRecording ? "Type shortcut…" : (shortcut?.displayString ?? "Click to record")
        let color: NSColor = shortcut == nil && !isRecording ? .secondaryLabelColor : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attrs)
    }
}
