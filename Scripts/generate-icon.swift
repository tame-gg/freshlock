#!/usr/bin/env swift
//
//  generate-icon.swift
//  Draws the FreshLock app icon (a dark squircle with a cyan→green padlock, in the
//  koels.net palette) at every required size and writes Packaging/AppIcon.icns.
//
//  Usage: swift Scripts/generate-icon.swift
//

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
let iconset = root.appendingPathComponent("Packaging/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func hex(_ v: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle tile with a small transparent margin.
    let margin = size * 0.06
    let tile = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = tile.width * 0.2237
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // Navy vertical gradient background.
    tilePath.addClip()
    let bg = NSGradient(colors: [hex(0x131A28), hex(0x0A0E16)])!
    bg.draw(in: tile, angle: -90)

    // Soft teal glow bottom-left.
    let glow = NSGradient(colors: [hex(0x6EE7B7).withAlphaComponent(0.22), .clear])!
    glow.draw(
        fromCenter: CGPoint(x: tile.minX + tile.width * 0.3, y: tile.minY + tile.height * 0.2),
        radius: 0,
        toCenter: CGPoint(x: tile.minX + tile.width * 0.3, y: tile.minY + tile.height * 0.2),
        radius: tile.width * 0.7,
        options: []
    )

    // Subtle inner hairline.
    hex(0xFFFFFF).withAlphaComponent(0.06).setStroke()
    let inner = NSBezierPath(roundedRect: tile.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
    inner.lineWidth = max(1, size / 512)
    inner.stroke()

    NSGraphicsContext.current!.cgContext.resetClip()

    // Padlock, centred.
    let bodyW = size * 0.42
    let bodyH = size * 0.30
    let bodyX = (size - bodyW) / 2
    let bodyY = size * 0.17
    let body = NSBezierPath(
        roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        xRadius: size * 0.06,
        yRadius: size * 0.06
    )

    // Shackle: a clean, tall U arching above the body.
    let archR = bodyW * 0.30 // arch radius = half the leg span
    let legBottom = bodyY + bodyH * 0.45 // starts inside the body (hidden by it)
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

    hex(0x7DE3FF).setStroke()
    shackle.stroke()

    // Body filled with cyan→green gradient (drawn over the shackle legs).
    let lock = NSGradient(colors: [hex(0x7DE3FF), hex(0x6EE7B7)])!
    lock.draw(in: body, angle: -60)

    // Keyhole.
    hex(0x0A0E16).setFill()
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

func writePNG(_: NSImage, pixels: Int, name: String) throws {
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
    try writePNG(NSImage(), pixels: px, name: name)
}

print("Wrote \(variants.count) PNGs to \(iconset.path)")
