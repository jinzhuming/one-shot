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

@Test @MainActor func appSettingsDefaultsToPicturesShotAndPreservesExistingDirectory() {
    let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    let expected = pictures.appendingPathComponent("Shot", isDirectory: true)
    #expect(AppSettings.defaultSaveDirectory.standardizedFileURL == expected.standardizedFileURL)

    let suiteName = "ShotTests.AppSettingsMigration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let existing = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)
    defaults.set(existing.path, forKey: "saveDirectory")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.saveDirectoryPath == existing.path)
    #expect(defaults.string(forKey: "saveDirectory") == existing.path)
}

@Test @MainActor func appSettingsPersistsAnnotationWindowPlacementAndRejectsUnknownValues() {
    let suiteName = "ShotTests.AppSettings.AnnotationWindowPlacement.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.annotationWindowPlacement == .inPlace)

    settings.annotationWindowPlacement = .centered
    #expect(defaults.string(forKey: "annotation.windowPlacement") == "centered")
    #expect(AppSettings(defaults: defaults).annotationWindowPlacement == .centered)

    defaults.set("unsupported", forKey: "annotation.windowPlacement")
    #expect(AppSettings(defaults: defaults).annotationWindowPlacement == .inPlace)
}

@Test func imageFilenameAddsCollisionSuffixes() {
    let preferred = "Shot 2026-09-03 at 09.05.07.png"
    var taken = Set([preferred, "Shot 2026-09-03 at 09.05.07 (2).png"])
    let next = ExportNaming.uniqueFilename(preferred: preferred) { taken.contains($0) }
    #expect(next == "Shot 2026-09-03 at 09.05.07 (3).png")

    taken.insert(next)
    #expect(ExportNaming.uniqueFilename(preferred: "fresh.jpg") { taken.contains($0) } == "fresh.jpg")
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

@Test @MainActor func overlayModeStateNormalizesAllInOneAndKeepsModesExclusive() {
    let state = OverlayModeState(mode: .allInOne)
    #expect(state.mode == .area)

    for mode in CaptureMode.selectableModes {
        state.select(mode)
        #expect(state.mode == mode)
        #expect(CaptureMode.selectableModes.filter { $0 == state.mode }.count == 1)
    }

    state.select(.allInOne)
    #expect(state.mode == .area)
}

@Test @MainActor func modeBarWindowStaysMouseInteractiveWithoutTakingKeyboardFocus() {
    let window = CaptureModeBarWindow(
        contentRect: CGRect(x: 0, y: 0, width: 268, height: 86),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(!window.canBecomeKey)
    #expect(!window.canBecomeMain)
    #expect(CaptureWindowLevels.modeBar.rawValue > CaptureWindowLevels.overlay.rawValue)
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

@Test @MainActor func selectionOverlayDrawsMaskAboveBackgroundImage() {
    let viewSize = CGSize(width: 200, height: 200)
    let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: viewSize))
    view.backgroundImage = solidImage(color: .white, size: viewSize)

    let window = OverlayWindow(
        contentRect: CGRect(origin: .zero, size: viewSize),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    view.visual = OverlayVisualState(
        highlightedWindow: CapturableWindow(
            windowID: 1,
            frame: CGRect(x: 50, y: 50, width: 100, height: 100),
            title: "测试窗口",
            bundleIdentifier: nil,
            processID: 2
        ),
        selectionRect: nil,
        dimOnly: false,
        holeIsWindow: true
    )

    let bitmap = cachedBitmap(for: view, size: viewSize)
    let outside = bitmap.colorAt(x: 20, y: 20)
    let inside = bitmap.colorAt(x: 100, y: 100)

    #expect(brightness(of: outside) < 0.8)
    #expect(brightness(of: inside) > 0.9)
}

@Test func windowSnapshotBuilderRejectsDockBeforeFrontmostApplicationWindow() {
    let dockID: CGWindowID = 10
    let unshareableID: CGWindowID = 15
    let frontID: CGWindowID = 20
    let backID: CGWindowID = 30
    let dictionaries = [
        windowDictionary(
            id: dockID,
            layer: 20,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            owner: "Dock",
            processID: 101
        ),
        windowDictionary(
            id: unshareableID,
            layer: 0,
            bounds: CGRect(x: 250, y: 120, width: 800, height: 500),
            owner: "Private",
            processID: 104
        ),
        windowDictionary(
            id: frontID,
            layer: 0,
            bounds: CGRect(x: 200, y: 100, width: 900, height: 600),
            owner: "Front",
            processID: 102
        ),
        windowDictionary(
            id: backID,
            layer: 0,
            bounds: CGRect(x: 100, y: 50, width: 1200, height: 800),
            owner: "Back",
            processID: 103
        )
    ]

    let windows = WindowSnapshotBuilder.build(
        dictionaries: dictionaries,
        primaryDisplayHeight: 1080,
        ourPID: 999,
        allowedWindowIDs: [dockID, frontID, backID]
    )

    #expect(windows.map(\.windowID) == [frontID, backID])
    let hits = WindowHitTesting.containing(
        CGPoint(x: 400, y: 600),
        in: windows.map(\.frame)
    )
    #expect(hits == [0, 1])
    #expect(windows[hits[0]].windowID == frontID)
}

@Test @MainActor func annotationCanvasDrawsLiveAnnotationAboveBaseImage() {
    let viewSize = CGSize(width: 200, height: 120)
    let view = AnnotationCanvasView(frame: CGRect(origin: .zero, size: viewSize))
    view.image = solidImage(color: .white, size: viewSize)
    view.annotations = [
        AnnotationObject(element: .line(
            start: CGPoint(x: 20, y: 60),
            end: CGPoint(x: 180, y: 60),
            style: AnnotationStyle(color: .systemRed, lineWidth: 6)
        ))
    ]

    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: viewSize),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = view

    let bitmap = cachedBitmap(for: view, size: viewSize)
    let containsRedPixel = (0..<Int(viewSize.width)).contains { x in
        (0..<Int(viewSize.height)).contains { y in
            guard let color = bitmap.colorAt(x: x, y: y),
                  let rgb = color.usingColorSpace(.deviceRGB) else { return false }
            return rgb.redComponent > 0.7
                && rgb.greenComponent < 0.6
                && rgb.blueComponent < 0.6
        }
    }

    #expect(containsRedPixel)
}

@Test @MainActor func editorHitTestingKeepsCanvasAndToolbarInTheirOwnRegions() {
    let image = solidImage(color: .white, size: CGSize(width: 240, height: 140))
    let session = EditSession(image: image)
    let arrangement = EditorArrangement(
        windowFrame: CGRect(x: 0, y: 0, width: 320, height: 260),
        canvasFrame: CGRect(x: 40, y: 100, width: 240, height: 140),
        toolbarFrame: CGRect(x: 40, y: 28, width: 240, height: 60),
        imageSize: image.size,
        toolbarAnchor: .below,
        keepsCaptureAligned: false
    )
    let content = EditorChromeView(
        session: session,
        arrangement: arrangement,
        onCopy: {},
        onSave: {},
        onClose: {}
    )
    content.frame = CGRect(origin: .zero, size: arrangement.windowFrame.size)
    let window = NSWindow(
        contentRect: content.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = content
    content.layoutSubtreeIfNeeded()

    let canvasHit = content.hitTest(CGPoint(
        x: content.canvas.frame.midX,
        y: content.canvas.frame.midY
    ))
    #expect(canvasHit === content.canvas)

    guard let toolbar = content.subviews.first(where: {
        $0 !== content.canvas
            && $0.frame.maxY <= arrangement.canvasFrame.minY
    }) else {
        Issue.record("The editor toolbar host should be installed below the canvas")
        return
    }
    let toolbarHit = content.hitTest(CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY))
    #expect(toolbarHit !== content.canvas)
}

@Test @MainActor func windowedEditorDocksAdaptiveToolbarAboveCanvasWithoutOverlap() {
    let image = solidImage(color: .white, size: CGSize(width: 480, height: 300))
    let session = EditSession(image: image)
    let layout = EditorLayout.windowed(
        imageSize: image.size,
        toolbarSize: CGSize(width: 520, height: 88),
        contentSize: CGSize(width: 720, height: 560)
    )
    let arrangement = EditorArrangement(
        windowFrame: CGRect(origin: .zero, size: layout.contentSize),
        canvasFrame: layout.canvasFrame,
        toolbarFrame: layout.toolbarFrame,
        imageSize: layout.imageSize,
        toolbarAnchor: .above,
        keepsCaptureAligned: false
    )
    let content = EditorChromeView(
        session: session,
        arrangement: arrangement,
        presentationStyle: .windowed,
        windowedLayout: layout,
        onCopy: {},
        onSave: {},
        onClose: {}
    )
    content.frame = CGRect(origin: .zero, size: layout.contentSize)
    let window = NSWindow(
        contentRect: content.frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = content
    content.layoutSubtreeIfNeeded()

    let initialToolbarHeight = content.toolbarFittingSize.height
    #expect(!content.mouseDownCanMoveWindow)
    #expect(abs(initialToolbarHeight - AnnotationChromeMetrics.windowToolbarHeight) < 0.5)
    #expect(content.canvas.frame.minX >= EditorLayout.windowedWorkspacePadding)
    #expect(content.canvas.frame.maxX <= content.bounds.maxX - EditorLayout.windowedWorkspacePadding)

    guard let toolbar = content.subviews.first(where: {
        $0 !== content.canvas && abs($0.frame.maxY - content.bounds.maxY) < 0.5
    }) else {
        Issue.record("The windowed editor should install a full-width top toolbar")
        return
    }
    #expect(abs(toolbar.frame.minX) < 0.5)
    #expect(abs(toolbar.frame.width - content.bounds.width) < 0.5)
    #expect(content.canvas.frame.maxY <= toolbar.frame.minY - EditorLayout.windowedWorkspacePadding + 0.5)
    #expect(toolbar.appearance == nil)
    let toolbarHit = content.hitTest(CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY))
    #expect(toolbarHit !== content.canvas)

    session.selectedTool = .select
    content.layoutSubtreeIfNeeded()
    #expect(abs(content.toolbarFittingSize.height - initialToolbarHeight) < 0.5)

    session.selectedTool = .highlighter
    content.layoutSubtreeIfNeeded()
    #expect(abs(content.toolbarFittingSize.height - initialToolbarHeight) < 0.5)
}

@Test @MainActor func annotationCanvasMapsMouseEventsThroughOffsetFlippedCanvas() {
    let canvas = AnnotationCanvasView(frame: CGRect(x: 50, y: 40, width: 200, height: 100))
    canvas.sourceImageSize = CGSize(width: 400, height: 200)
    let spy = CanvasEventSpy()
    canvas.delegate = spy

    let parent = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
    parent.addSubview(canvas)
    let window = NSWindow(
        contentRect: parent.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = parent

    let start = canvas.convert(CGPoint(x: 20, y: 30), to: nil)
    let end = canvas.convert(CGPoint(x: 180, y: 80), to: nil)
    let down = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: start,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
    )!
    let drag = NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: end,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 2,
        clickCount: 1,
        pressure: 1
    )!
    let up = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: end,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 3,
        clickCount: 1,
        pressure: 1
    )!

    canvas.mouseDown(with: down)
    canvas.mouseDragged(with: drag)
    canvas.mouseUp(with: up)

    #expect(spy.events.count == 3)
    #expect(spy.events.first?.point == CGPoint(x: 40, y: 60))
    #expect(spy.events.last?.point == CGPoint(x: 360, y: 160))
}

@Test func editorWindowLevelLeavesSystemScreenSaverAndPrivacyWindowsUncovered() {
    #expect(CaptureWindowLevels.editor.rawValue > CaptureWindowLevels.overlay.rawValue)
    #expect(CaptureWindowLevels.editor.rawValue < Int(CGWindowLevelForKey(.screenSaverWindow)))
}

private func solidImage(color: NSColor, size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

private func windowDictionary(
    id: CGWindowID,
    layer: Int,
    bounds: CGRect,
    owner: String,
    processID: pid_t
) -> [String: Any] {
    [
        kCGWindowNumber as String: NSNumber(value: id),
        kCGWindowLayer as String: NSNumber(value: layer),
        kCGWindowBounds as String: bounds.dictionaryRepresentation,
        kCGWindowOwnerName as String: owner,
        kCGWindowOwnerPID as String: NSNumber(value: processID)
    ]
}

private func cachedBitmap(for view: NSView, size: CGSize) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

private func brightness(of color: NSColor?) -> CGFloat {
    guard let rgb = color?.usingColorSpace(.deviceRGB) else { return 0 }
    return max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
}

@MainActor
private final class CanvasEventSpy: NSObject, AnnotationCanvasDelegate {
    var events: [CanvasEvent] = []

    func canvasDidReceive(_ event: CanvasEvent) {
        events.append(event)
    }

    func canvasDidBeginText(at imagePoint: CGPoint, replacing id: UUID?) {}
    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint, replacing id: UUID?) {}
    func canvasDidCancelText() {}
}
