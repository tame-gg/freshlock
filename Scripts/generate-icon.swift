#!/usr/bin/env swift
//
//  generate-icon.swift
//  FreshLock dock / app icon for macOS Sequoia–Tahoe.
//
//  Soft single-hue teal field + crisp white lock silhouette. Subtle material
//  depth only (same-hue tonal wash, soft top sheen). No navy canvas, no
//  cyan→green marketing gradient, no radial glow blob.
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

// Soft teal field (hue held; value only shifts for material depth).
let fieldTop = hex(0x5EBFC8)
let fieldBottom = hex(0x3A97A2)
// Keyhole / punch uses the deeper field tone so the cut reads clean.
let punch = hex(0x2F7F8A)
let lockWhite = hex(0xFFFFFF)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // Full-bleed field. System applies the Dock squircle mask.
    NSGradient(colors: [fieldTop, fieldBottom])!.draw(in: bounds, angle: -90)

    // Soft top sheen: directional material light across the upper face,
    // not a radial glow parked behind the mark.
    if size >= 48 {
        let sheenRect = NSRect(x: 0, y: size * 0.52, width: size, height: size * 0.48)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.22),
            NSColor.white.withAlphaComponent(0.0)
        ])!.draw(in: sheenRect, angle: -90)
    }

    // Lock geometry: optically centered, bold enough for 16–32pt Dock.
    let bodyW = size * 0.40
    let bodyH = size * 0.30
    let bodyX = (size - bodyW) / 2
    let bodyY = size * 0.20
    let corner = size * 0.072

    let archR = bodyW * 0.295
    let stroke = size * 0.070
    let legBottom = bodyY + bodyH * 0.42
    let archCenterY = bodyY + bodyH + size * 0.048
    let cx = size / 2
    let legX1 = cx - archR
    let legX2 = cx + archR

    // Tight contact shadow under the lock (large sizes only).
    if size >= 128 {
        let shadow = NSBezierPath(
            roundedRect: NSRect(
                x: bodyX + size * 0.02,
                y: bodyY - size * 0.018,
                width: bodyW - size * 0.04,
                height: size * 0.04
            ),
            xRadius: size * 0.02,
            yRadius: size * 0.02
        )
        hex(0x1A5A63, alpha: 0.28).setFill()
        shadow.fill()
    }

    // Shackle (white).
    let shackle = NSBezierPath()
    shackle.lineWidth = stroke
    shackle.lineCapStyle = .round
    shackle.lineJoinStyle = .round
    shackle.move(to: CGPoint(x: legX1, y: legBottom))
    shackle.line(to: CGPoint(x: legX1, y: archCenterY))
    shackle.appendArc(
        withCenter: CGPoint(x: cx, y: archCenterY),
        radius: archR,
        startAngle: 180,
        endAngle: 0,
        clockwise: true
    )
    shackle.line(to: CGPoint(x: legX2, y: legBottom))
    lockWhite.setStroke()
    shackle.stroke()

    // Body (white).
    let body = NSBezierPath(
        roundedRect: NSRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        xRadius: corner,
        yRadius: corner
    )
    lockWhite.setFill()
    body.fill()

    // Keyhole punch. Scale up slightly at tiny sizes so it survives.
    let holeScale: CGFloat = size < 32 ? 1.25 : 1.0
    let holeR = size * 0.038 * holeScale
    let holeC = CGPoint(x: cx, y: bodyY + bodyH * 0.60)
    punch.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: holeC.x - holeR,
        y: holeC.y - holeR,
        width: holeR * 2,
        height: holeR * 2
    )).fill()

    let slotW = size * 0.030 * holeScale
    let slotH = bodyH * 0.38
    let slot = NSBezierPath(
        roundedRect: NSRect(
            x: cx - slotW / 2,
            y: bodyY + bodyH * 0.16,
            width: slotW,
            height: slotH
        ),
        xRadius: slotW / 2,
        yRadius: slotW / 2
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
