#!/usr/bin/env swift
//
//  generate-icon.swift
//  Draws the FreshLock app icon: a quiet, system-like mark (flat charcoal
//  canvas + solid systemTeal-adjacent lock). No navy marketing gradient,
//  no cyan→green fill, no radial glow.
//
//  Usage: swift Scripts/generate-icon.swift
//  Writes Packaging/AppIcon.iconset/*.png and Packaging/AppIcon.icns
//  (build-app.sh copies AppIcon.icns into the app bundle).
//

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
let packaging = root.appendingPathComponent("Packaging")
let iconset = packaging.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func hex(_ v: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

/// Neutral charcoal (system gray family), not cool navy.
let canvas = hex(0x2C2C2E)
/// Quiet systemTeal-adjacent fill; single tone, no gradient.
let lockFill = hex(0x5AC8D8)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Full-bleed flat canvas. System applies the dock squircle mask.
    canvas.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    // Padlock, centred. Solid tonal fill only.
    let bodyW = size * 0.42
    let bodyH = size * 0.30
    let bodyX = (size - bodyW) / 2
    let bodyY = size * 0.17
    let body = NSBezierPath(
        roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        xRadius: size * 0.06,
        yRadius: size * 0.06
    )

    // Shackle: tall U arching above the body.
    let archR = bodyW * 0.30
    let legBottom = bodyY + bodyH * 0.45
    let archCenterY = bodyY + bodyH + size * 0.055
    let legX1 = size / 2 - archR
    let legX2 = size / 2 + archR
    let shackle = NSBezierPath()
    shackle.lineWidth = size * 0.052
    shackle.lineCapStyle = .round
    shackle.move(to: CGPoint(x: legX1, y: legBottom))
    shackle.line(to: CGPoint(x: legX1, y: archCenterY))
    shackle.appendArc(
        withCenter: CGPoint(x: size / 2, y: archCenterY),
        radius: archR,
        startAngle: 180,
        endAngle: 0,
        clockwise: true
    )
    shackle.line(to: CGPoint(x: legX2, y: legBottom))

    lockFill.setStroke()
    shackle.stroke()

    lockFill.setFill()
    body.fill()

    // Keyhole punched in canvas tone so the lock reads as one solid mark.
    canvas.setFill()
    let holeR = size * 0.035
    let holeC = CGPoint(x: size / 2, y: bodyY + bodyH * 0.58)
    NSBezierPath(ovalIn: CGRect(x: holeC.x - holeR, y: holeC.y - holeR, width: holeR * 2, height: holeR * 2)).fill()
    let slot = NSBezierPath(
        roundedRect: CGRect(
            x: holeC.x - size * 0.014,
            y: bodyY + bodyH * 0.18,
            width: size * 0.028,
            height: bodyH * 0.40
        ),
        xRadius: size * 0.014,
        yRadius: size * 0.014
    )
    slot.fill()

    image.unlockFocus()
    return image
}

func writePNG(pixels: Int, name: String) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent(name))
}

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (px, name) in variants {
    try writePNG(pixels: px, name: name)
}

print("Wrote \(variants.count) PNGs to \(iconset.path)")

let icns = packaging.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}
print("Wrote \(icns.path)")
