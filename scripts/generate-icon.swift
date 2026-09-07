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

private enum IconDetail: Equatable {
    case full
    case compact

    var frameScale: CGFloat {
        switch self {
        case .full: 0.48
        case .compact: 0.45
        }
    }

    var armScale: CGFloat {
        switch self {
        case .full: 0.078
        case .compact: 0.082
        }
    }

    var strokeScale: CGFloat {
        switch self {
        case .full: 0.028
        case .compact: 0.054
        }
    }

    var lensScale: CGFloat {
        switch self {
        case .full: 0.34
        case .compact: 0.29
        }
    }
}

private func drawViewfinderMark(
    in rect: NSRect,
    detail: IconDetail,
    color: NSColor
) {
    let size = min(rect.width, rect.height)
    let frame = size * detail.frameScale
    let left = rect.midX - frame / 2
    let right = rect.midX + frame / 2
    let bottom = rect.midY - frame / 2
    let top = rect.midY + frame / 2
    let arm = size * detail.armScale
    let stroke = size * detail.strokeScale
    let cornerRadius = stroke * 0.9

    color.setStroke()
    let topLeft = NSBezierPath()
    topLeft.move(to: NSPoint(x: left + arm, y: top))
    topLeft.line(to: NSPoint(x: left + cornerRadius, y: top))
    topLeft.curve(
        to: NSPoint(x: left, y: top - cornerRadius),
        controlPoint1: NSPoint(x: left + cornerRadius * 0.45, y: top),
        controlPoint2: NSPoint(x: left, y: top - cornerRadius * 0.45)
    )
    topLeft.line(to: NSPoint(x: left, y: top - arm))
    roundedStroke(topLeft, width: stroke)

    let topRight = NSBezierPath()
    topRight.move(to: NSPoint(x: right - arm, y: top))
    topRight.line(to: NSPoint(x: right - cornerRadius, y: top))
    topRight.curve(
        to: NSPoint(x: right, y: top - cornerRadius),
        controlPoint1: NSPoint(x: right - cornerRadius * 0.45, y: top),
        controlPoint2: NSPoint(x: right, y: top - cornerRadius * 0.45)
    )
    topRight.line(to: NSPoint(x: right, y: top - arm))
    roundedStroke(topRight, width: stroke)

    let bottomLeft = NSBezierPath()
    bottomLeft.move(to: NSPoint(x: left + arm, y: bottom))
    bottomLeft.line(to: NSPoint(x: left + cornerRadius, y: bottom))
    bottomLeft.curve(
        to: NSPoint(x: left, y: bottom + cornerRadius),
        controlPoint1: NSPoint(x: left + cornerRadius * 0.45, y: bottom),
        controlPoint2: NSPoint(x: left, y: bottom + cornerRadius * 0.45)
    )
    bottomLeft.line(to: NSPoint(x: left, y: bottom + arm))
    roundedStroke(bottomLeft, width: stroke)

    let bottomRight = NSBezierPath()
    bottomRight.move(to: NSPoint(x: right - arm, y: bottom))
    bottomRight.line(to: NSPoint(x: right - cornerRadius, y: bottom))
    bottomRight.curve(
        to: NSPoint(x: right, y: bottom + cornerRadius),
        controlPoint1: NSPoint(x: right - cornerRadius * 0.45, y: bottom),
        controlPoint2: NSPoint(x: right, y: bottom + cornerRadius * 0.45)
    )
    bottomRight.line(to: NSPoint(x: right, y: bottom + arm))
    roundedStroke(bottomRight, width: stroke)
}

private func drawLens(in rect: NSRect, detail: IconDetail) {
    let size = min(rect.width, rect.height)
    let diameter = size * detail.lensScale
    let lensRect = NSRect(
        x: rect.midX - diameter / 2,
        y: rect.midY - diameter / 2,
        width: diameter,
        height: diameter
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = size * 0.026
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.set()
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(ovalIn: lensRect).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.11).setFill()
    NSBezierPath(ovalIn: lensRect).fill()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: lensRect.insetBy(dx: diameter * 0.045, dy: diameter * 0.045)).addClip()
    let lensGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.68, green: 0.90, blue: 1.0, alpha: 0.44),
        NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.68, alpha: 0.72)
    ])
    lensGradient?.draw(in: lensRect, angle: 135)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.56).setStroke()
    let ring = NSBezierPath(ovalIn: lensRect.insetBy(dx: size * 0.008, dy: size * 0.008))
    ring.lineWidth = size * 0.014
    ring.stroke()

    if detail == .full {
        NSColor.white.withAlphaComponent(0.20).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: lensRect.minX + diameter * 0.20,
            y: lensRect.maxY - diameter * 0.34,
            width: diameter * 0.22,
            height: diameter * 0.10
        )).fill()

        NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.56, alpha: 0.48).setFill()
        let aperture = diameter * 0.40
        NSBezierPath(ovalIn: NSRect(
            x: rect.midX - aperture / 2,
            y: rect.midY - aperture / 2,
            width: aperture,
            height: aperture
        )).fill()

        NSColor.white.withAlphaComponent(0.86).setFill()
        let dot = size * 0.025
        NSBezierPath(ovalIn: NSRect(
            x: rect.midX - dot / 2,
            y: rect.midY - dot / 2,
            width: dot,
            height: dot
        )).fill()
    }
}

private func renderIcon(size: CGFloat, detail: IconDetail) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.43, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.30, blue: 0.70, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.82, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: 34)

    // Keep the background square and unmasked; macOS applies the app-icon shape
    // in Finder and the Dock. Use a small glow instead of a large decorative
    // shape so the lens remains the visual focus.
    NSColor.white.withAlphaComponent(0.035).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: size * 0.02,
        y: size * 0.72,
        width: size * 0.40,
        height: size * 0.30
    )).fill()

    NSGraphicsContext.current?.shouldAntialias = true
    drawLens(in: rect, detail: detail)

    drawViewfinderMark(
        in: rect,
        detail: detail,
        color: NSColor.white.withAlphaComponent(0.64)
    )

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

private func maskedIcon(_ image: NSImage) -> NSImage {
    let size = image.size.width
    let rect = NSRect(origin: .zero, size: image.size)
    let masked = NSImage(size: image.size)
    masked.lockFocus()

    // The asset catalog receives the unmasked square source above. The
    // SwiftPM fallback is an icns file, so apply the macOS rounded-rectangle
    // shape here for legacy packaging that does not contain Assets.car.
    NSGraphicsContext.saveGraphicsState()
    let radius = size * 0.215
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    masked.unlockFocus()
    return masked
}

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

let icnsIconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Shot-iconset-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: icnsIconset, withIntermediateDirectories: true)

for entry in entries {
    let detail: IconDetail = entry.pixels <= 64 ? .compact : .full
    let renderScale: CGFloat = entry.pixels <= 64 ? 8 : 1
    let image = renderIcon(size: CGFloat(entry.pixels) * renderScale, detail: detail)
    let data = pngData(image, pixels: entry.pixels)
    try data.write(to: iconset.appendingPathComponent(entry.name))
    try data.write(to: xcassets.appendingPathComponent(entry.name))

    let icnsData = pngData(maskedIcon(image), pixels: entry.pixels)
    try icnsData.write(to: icnsIconset.appendingPathComponent(entry.name))
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
process.arguments = ["-c", "icns", "-o", icns.path, icnsIconset.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    try? FileManager.default.removeItem(at: icnsIconset)
    throw NSError(domain: "generate-icon", code: Int(process.terminationStatus))
}
try FileManager.default.removeItem(at: icnsIconset)

print("Wrote \(icns.path)")
