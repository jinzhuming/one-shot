#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().path)
let support = root.appendingPathComponent("Support")
let iconset = support.appendingPathComponent("Shot.iconset")
let xcassets = support.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: xcassets, withIntermediateDirectories: true)
_ = NSApplication.shared

private func roundedStroke(_ path: NSBezierPath, width: CGFloat) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

private func drawViewfinderMark(in rect: NSRect) {
    let size = min(rect.width, rect.height)
    let left = rect.midX - size * 0.31
    let right = rect.midX + size * 0.31
    let bottom = rect.midY - size * 0.31
    let top = rect.midY + size * 0.31
    let arm = size * 0.15
    let stroke = size * 0.072

    NSColor.white.setStroke()
    let topLeft = NSBezierPath()
    topLeft.move(to: NSPoint(x: left + arm, y: top))
    topLeft.line(to: NSPoint(x: left, y: top))
    topLeft.line(to: NSPoint(x: left, y: top - arm))
    roundedStroke(topLeft, width: stroke)

    let topRight = NSBezierPath()
    topRight.move(to: NSPoint(x: right - arm, y: top))
    topRight.line(to: NSPoint(x: right, y: top))
    topRight.line(to: NSPoint(x: right, y: top - arm))
    roundedStroke(topRight, width: stroke)

    let bottomLeft = NSBezierPath()
    bottomLeft.move(to: NSPoint(x: left + arm, y: bottom))
    bottomLeft.line(to: NSPoint(x: left, y: bottom))
    bottomLeft.line(to: NSPoint(x: left, y: bottom + arm))
    roundedStroke(bottomLeft, width: stroke)

    let bottomRight = NSBezierPath()
    bottomRight.move(to: NSPoint(x: right - arm, y: bottom))
    bottomRight.line(to: NSPoint(x: right, y: bottom))
    bottomRight.line(to: NSPoint(x: right, y: bottom + arm))
    roundedStroke(bottomRight, width: stroke)

    let lensRadius = size * 0.125
    let lens = NSBezierPath(ovalIn: NSRect(
        x: rect.midX - lensRadius,
        y: rect.midY - lensRadius,
        width: lensRadius * 2,
        height: lensRadius * 2
    ))
    roundedStroke(lens, width: stroke)

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: rect.midX - size * 0.032,
        y: rect.midY - size * 0.032,
        width: size * 0.064,
        height: size * 0.064
    )).fill()
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.34, blue: 0.91, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.82, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: 35)

    // A restrained light sweep adds depth without baking in a rounded-rectangle
    // mask; macOS applies the app-icon shape in Finder and the Dock.
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: size * -0.28,
        y: size * 0.56,
        width: size * 0.95,
        height: size * 0.72
    )).fill()

    NSGraphicsContext.current?.shouldAntialias = true
    drawViewfinderMark(in: rect)

    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, pixels: Int) -> Data {
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
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let master = renderIcon(size: 1024)
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    let data = pngData(master, pixels: entry.pixels)
    try data.write(to: iconset.appendingPathComponent(entry.name))
    try data.write(to: xcassets.appendingPathComponent(entry.name))
}

let contents = """
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16", "scale" : "1x", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "size" : "16x16", "scale" : "2x", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "1x", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "size" : "32x32", "scale" : "2x", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try contents.write(to: xcassets.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let catalog = """
{
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try catalog.write(
    to: support.appendingPathComponent("Assets.xcassets/Contents.json"),
    atomically: true,
    encoding: .utf8
)

let icns = support.appendingPathComponent("Shot.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "generate-icon", code: Int(process.terminationStatus))
}

print("Wrote \(icns.path)")
