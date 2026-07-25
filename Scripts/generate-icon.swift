#!/usr/bin/env swift
//
//  generate-icon.swift
//  FreshLock dock / app icon for macOS Sequoia–Tahoe.
//
//  Soft single-hue teal field + white shield-lock silhouette (lock + shield
//  fused into one mark). Subtle same-hue material depth only. No navy canvas,
//  no cyan→green marketing gradient, no radial glow blob.
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

func hex(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: alpha
    )
}

// Soft teal field: hue held, value shifts for material depth (not multi-hue marketing).
let fieldTop = hex(0x62C2CB)
let fieldBottom = hex(0x348F9A)
let punch = hex(0x2A7882)
let mark = hex(0xFFFFFF)

/// Soft shield body (FreshLock = lock + shield), y-up AppKit coords.
func shieldBody(in size: CGFloat) -> NSBezierPath {
    let cx = size / 2
    let top = size * 0.40
    let bottom = size * 0.12
    let halfW = size * 0.235
    let left = cx - halfW
    let right = cx + halfW
    let topR = size * 0.065
    let path = NSBezierPath()

    // Top edge with rounded corners, then sides taper into a soft tip.
    path.move(to: CGPoint(x: left + topR, y: top))
    path.line(to: CGPoint(x: right - topR, y: top))
    path.appendArc(
        withCenter: CGPoint(x: right - topR, y: top - topR),
        radius: topR,
        startAngle: 90,
        endAngle: 0,
        clockwise: true
    )
    path.curve(
        to: CGPoint(x: cx, y: bottom),
        controlPoint1: CGPoint(x: right, y: top - size * 0.22),
        controlPoint2: CGPoint(x: right - size * 0.02, y: bottom + size * 0.10)
    )
    path.curve(
        to: CGPoint(x: left, y: top - topR),
        controlPoint1: CGPoint(x: left + size * 0.02, y: bottom + size * 0.10),
        controlPoint2: CGPoint(x: left, y: top - size * 0.22)
    )
    path.appendArc(
        withCenter: CGPoint(x: left + topR, y: top - topR),
        radius: topR,
        startAngle: 180,
        endAngle: 90,
        clockwise: true
    )
    path.close()
    return path
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // Full-bleed field. System applies the Dock squircle mask.
    NSGradient(colors: [fieldTop, fieldBottom])!.draw(in: bounds, angle: -90)

    // Soft top sheen: directional material light, not a halo behind the mark.
    if size >= 48 {
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0.0)
        ])!.draw(
            in: NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45),
            angle: -90
        )
    }

    let cx = size / 2
    let bodyTop = size * 0.40
    let halfW = size * 0.235

    // Shackle arching above the shield.
    let archR = halfW * 0.72
    let stroke = size * 0.068
    let legInset = size * 0.018
    let legBottom = bodyTop - size * 0.02
    let archCenterY = bodyTop + size * 0.095
    let legX1 = cx - archR
    let legX2 = cx + archR

    let shackle = NSBezierPath()
    shackle.lineWidth = stroke
    shackle.lineCapStyle = .round
    shackle.lineJoinStyle = .round
    shackle.move(to: CGPoint(x: legX1, y: legBottom - legInset))
    shackle.line(to: CGPoint(x: legX1, y: archCenterY))
    shackle.appendArc(
        withCenter: CGPoint(x: cx, y: archCenterY),
        radius: archR,
        startAngle: 180,
        endAngle: 0,
        clockwise: true
    )
    shackle.line(to: CGPoint(x: legX2, y: legBottom - legInset))
    mark.setStroke()
    shackle.stroke()

    // Shield body.
    let body = shieldBody(in: size)
    mark.setFill()
    body.fill()

    // Keyhole punch (scaled up at tiny sizes for legibility).
    let holeScale: CGFloat = size < 32 ? 1.3 : (size < 64 ? 1.1 : 1.0)
    let holeR = size * 0.040 * holeScale
    let holeC = CGPoint(x: cx, y: size * 0.318)
    punch.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: holeC.x - holeR,
        y: holeC.y - holeR,
        width: holeR * 2,
        height: holeR * 2
    )).fill()

    let slotW = size * 0.032 * holeScale
    let slotH = size * 0.095
    NSBezierPath(
        roundedRect: NSRect(
            x: cx - slotW / 2,
            y: size * 0.195,
            width: slotW,
            height: slotH
        ),
        xRadius: slotW / 2,
        yRadius: slotW / 2
    ).fill()

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
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.shouldAntialias = true
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
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
