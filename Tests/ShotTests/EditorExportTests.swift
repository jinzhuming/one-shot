import AppKit
import CoreGraphics
import Foundation
import ShotKit
import Testing
@testable import Shot

@Test @MainActor func committedTextIsPresentInFlattenedEditorImage() {
    let width = 320
    let height = 180
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let base = NSImage(
        cgImage: context.makeImage()!,
        size: CGSize(width: width, height: height)
    )
    var document = AnnotationDocument(baseImage: base)

    document.commit(.text(
        "Shot",
        origin: CGPoint(x: 24, y: 24),
        style: AnnotationStyle(color: .systemRed, lineWidth: 4)
    ))

    let flattened = document.flattened()
    var proposed = CGRect(origin: .zero, size: flattened.size)
    let image = flattened.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
    let data = image.dataProvider!.data! as Data
    let bytes = [UInt8](data)
    let hasNonWhitePixel = stride(from: 0, to: bytes.count, by: 4).contains { index in
        bytes[index] < 245 || bytes[index + 1] < 245 || bytes[index + 2] < 245
    }
    #expect(hasNonWhitePixel)
}

@Test @MainActor func appSettingsRejectsInvalidHistorySelection() {
    let suiteName = "ShotTests.AppSettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)

    defaults.set([
        "x": "not-a-number",
        "y": 20.0,
        "w": 100.0,
        "h": 80.0,
        "displayID": 42
    ], forKey: "lastSelection")
    #expect(settings.lastSelection == nil)

    defaults.set([
        "x": 10.0,
        "y": 20.0,
        "w": 100.0,
        "h": 80.0,
        "displayID": 42
    ], forKey: "lastSelection")
    #expect(settings.lastSelection == LastSelection(
        rect: CGRect(x: 10, y: 20, width: 100, height: 80),
        displayID: 42
    ))
}

@Test @MainActor func appSettingsDefaultsToDownloadsAndMigratesLegacyDirectory() {
    let downloads = AppSettings.defaultSaveDirectory
    #expect(downloads.standardizedFileURL == FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").standardizedFileURL)

    let suiteName = "ShotTests.AppSettingsMigration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    defaults.set(pictures.appendingPathComponent("Shot", isDirectory: true).path, forKey: "saveDirectory")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.saveDirectoryPath == downloads.path)
    #expect(defaults.string(forKey: "saveDirectory") == downloads.path)
}

@Test @MainActor func hotkeyCenterReadsInjectedDefaults() throws {
    let suiteName = "ShotTests.HotkeyCenter.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let hotkey = Hotkey(keyCode: 18, modifierRaw: NSEvent.ModifierFlags.command.rawValue, character: "1")
    defaults.set(try JSONEncoder().encode(hotkey), forKey: "hotkey.captureArea")

    let center = HotkeyCenter(defaults: defaults)
    #expect(center.hotkey(for: .captureArea) == hotkey)
}

@Test @MainActor func recordingFilenameAddsCollisionSuffix() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShotRecordingTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let date = Date(timeIntervalSince1970: 1_756_890_307)
    let firstName = ExportNaming.filename(fileExtension: "mp4", date: date)
    let firstURL = directory.appendingPathComponent(firstName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: firstURL)

    let nextURL = try VideoExporter.recordingURL(in: directory, date: date)
    let expectedBase = firstURL.deletingPathExtension().lastPathComponent
    #expect(nextURL.lastPathComponent == "\(expectedBase) (2).mp4")
}
