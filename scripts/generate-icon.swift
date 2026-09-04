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

func whiteSymbol(pointSize: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size), from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    return tinted
}

func renderIcon(size: CGFloat) -> NSImage {
    let symbol = whiteSymbol(pointSize: size * 0.42)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: size * 0.015, dy: size * 0.015),
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )
    background.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.82, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.96, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: 90)

    NSColor.white.withAlphaComponent(0.18).setFill()
    let highlight = NSBezierPath(ovalIn: NSRect(
        x: size * -0.15,
        y: size * 0.45,
        width: size * 1.3,
        height: size * 0.8
    ))
    highlight.fill()

    if let symbol {
        let symbolRect = NSRect(
            x: (size - symbol.size.width) / 2,
            y: (size - symbol.size.height) / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

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
