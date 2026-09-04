import AppKit
import Testing
@testable import ShotKit

@Test func localRectConvertsDisplayOrigin() {
    let display = CGRect(x: 1920, y: 0, width: 1512, height: 982)
    let global = CGRect(x: 2000, y: 100, width: 320, height: 200)
    let local = RectMath.localRect(global, in: display)
    #expect(abs(local.origin.x - 80) < 0.001)
    #expect(abs(local.origin.y - 100) < 0.001)
    #expect(abs(local.size.width - 320) < 0.001)
    #expect(abs(local.size.height - 200) < 0.001)
}

@Test func displaySourceRectFlipsCocoaYToDisplayTopLeft() {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let bottom = CGRect(x: 100, y: 40, width: 200, height: 150)
    let mainSource = RectMath.displaySourceRect(cocoaGlobal: bottom, screenFrame: main)
    #expect(abs(mainSource.origin.x - 100) < 0.001)
    #expect(abs(mainSource.origin.y - 710) < 0.001)
    #expect(abs(mainSource.width - 200) < 0.001)
    #expect(abs(mainSource.height - 150) < 0.001)

    let right = CGRect(x: 1920, y: 0, width: 1512, height: 982)
    let global = CGRect(x: 2000, y: 100, width: 320, height: 200)
    let rightSource = RectMath.displaySourceRect(cocoaGlobal: global, screenFrame: right)
    #expect(abs(rightSource.origin.x - 80) < 0.001)
    #expect(abs(rightSource.origin.y - 682) < 0.001)
    #expect(abs(rightSource.width - 320) < 0.001)
    #expect(abs(rightSource.height - 200) < 0.001)
}

@Test func pixelCropRectFlipsAndScalesRetinaCoordinates() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let selection = CGRect(x: 100, y: 40, width: 200, height: 150)
    let crop = RectMath.pixelCropRect(
        cocoaGlobal: selection,
        screenFrame: screen,
        pixelSize: CGSize(width: 2880, height: 1800),
        scale: 2
    )

    #expect(crop == CGRect(x: 200, y: 1420, width: 400, height: 300))
}

@Test func pixelCropRectHandlesNonZeroDisplayOriginAndEdges() {
    let screen = CGRect(x: 1920, y: -120, width: 1512, height: 982)
    let selection = CGRect(x: 2000, y: -20, width: 320, height: 200)
    let crop = RectMath.pixelCropRect(
        cocoaGlobal: selection,
        screenFrame: screen,
        pixelSize: CGSize(width: 1512, height: 982),
        scale: 1
    )

    #expect(crop == CGRect(x: 80, y: 682, width: 320, height: 200))

    let full = RectMath.pixelCropRect(
        cocoaGlobal: screen,
        screenFrame: screen,
        pixelSize: CGSize(width: 1512, height: 982),
        scale: 1
    )
    #expect(full == CGRect(x: 0, y: 0, width: 1512, height: 982))
}

@Test func pixelCropRectRejectsCrossDisplayAndInvalidRects() {
    let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
    let pixels = CGSize(width: 200, height: 200)
    #expect(RectMath.pixelCropRect(
        cocoaGlobal: CGRect(x: 90, y: 10, width: 20, height: 20),
        screenFrame: screen,
        pixelSize: pixels,
        scale: 2
    ) == nil)
    #expect(RectMath.pixelCropRect(
        cocoaGlobal: CGRect(x: 10, y: 10, width: 0, height: 20),
        screenFrame: screen,
        pixelSize: pixels,
        scale: 2
    ) == nil)
    #expect(RectMath.pixelCropRect(
        cocoaGlobal: CGRect(x: 10, y: 10, width: 20, height: 20),
        screenFrame: screen,
        pixelSize: pixels,
        scale: .nan
    ) == nil)
}

@Test func windowCropKeepsExactFrameWithoutShadowPadding() {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let window = CGRect(x: 240, y: 180, width: 800, height: 600)
    let crop = RectMath.pixelCropRect(
        cocoaGlobal: window,
        screenFrame: screen,
        pixelSize: CGSize(width: 3200, height: 2000),
        scale: 2
    )

    // Both shadow variants must use the same SCWindow frame. Shadow handling
    // changes pixels, never the output bounds or an undocumented padding.
    #expect(crop?.size == CGSize(width: 1600, height: 1200))
}

@Test func shadowedWindowUsesSingleWindowCaptureRoute() {
    #expect(WindowCapturePolicy.route(includeShadow: true) == .singleWindow)
    #expect(WindowCapturePolicy.route(includeShadow: false) == .displaySnapshot)
}

@Test func cocoaRectFlipsFromCGWindowOrigin() {
    let cg = CGRect(x: 100, y: 50, width: 400, height: 300)
    let cocoa = RectMath.cocoaRect(fromCGWindowBounds: cg, primaryHeight: 982)
    #expect(abs(cocoa.origin.x - 100) < 0.001)
    #expect(abs(cocoa.origin.y - 632) < 0.001)
    #expect(cocoa.size == cg.size)
}

@Test func exportFilenameMatchesSystemScreenshotStyle() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9, minute: 5, second: 7))!
    #expect(
        ExportNaming.filename(fileExtension: "png", date: date, timeZone: TimeZone(secondsFromGMT: 0)!)
            == "Shot 2026-09-03 at 09.05.07.png"
    )
}

@Test func recordingDimensionsArePositiveAndEvenPixels() {
    #expect(RecordingLayout.evenPixelSize(points: 320, scale: 2) == 640)
    #expect(RecordingLayout.evenPixelSize(points: 100.5, scale: 2) == 202)
    #expect(RecordingLayout.evenPixelSize(points: 0, scale: 2) == 2)
    #expect(RecordingLayout.evenPixelSize(points: 100, scale: .nan) == 2)
}

@Test func recordingPreviewFramesStartAtLowerLeftAndStackUp() {
    let visibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let frames = RecordingLayout.previewFrames(
        count: 4,
        windowSize: CGSize(width: 360, height: 240),
        visibleFrame: visibleFrame
    )

    #expect(frames.count == 4)
    #expect(frames[0].origin == CGPoint(x: 116, y: 66))
    #expect(frames[1].origin == CGPoint(x: 116, y: 318))
    #expect(frames[2].origin == CGPoint(x: 116, y: 570))
    #expect(frames[3].origin == CGPoint(x: 488, y: 66))
    #expect(frames.allSatisfy { visibleFrame.contains($0) })
}

@Test func hotkeyRoundTripAndDisplayOrder() throws {
    let hotkey = Hotkey.defaultAllInOne
    let data = try JSONEncoder().encode(hotkey)
    let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
    #expect(decoded == hotkey)
    #expect(hotkey.keyCode == 0)
    #expect(hotkey.character == "a")
    #expect(hotkey.displayString == "⇧⌘A")
    #expect(hotkey.carbonModifiers != 0)
    #expect(Hotkey.defaultRecording.displayString == "⇧⌘6")
}

@Test func canvasMappingScalesViewToImage() {
    let viewPoint = CGPoint(x: 100, y: 50)
    let viewSize = CGSize(width: 200, height: 100)
    let imageSize = CGSize(width: 800, height: 400)
    let imagePoint = CanvasMapping.imagePoint(viewPoint: viewPoint, viewSize: viewSize, imageSize: imageSize)
    #expect(abs(imagePoint.x - 400) < 0.001)
    #expect(abs(imagePoint.y - 200) < 0.001)
    let roundTrip = CanvasMapping.viewPoint(imagePoint: imagePoint, viewSize: viewSize, imageSize: imageSize)
    #expect(abs(roundTrip.x - viewPoint.x) < 0.001)
    #expect(abs(roundTrip.y - viewPoint.y) < 0.001)
}

@Test func selectionGeometrySquareAndSpaceMove() {
    let start = CGPoint(x: 10, y: 10)
    let current = CGPoint(x: 30, y: 20)
    let free = SelectionGeometry.rect(from: start, to: current, square: false)
    #expect(abs(free.width - 20) < 0.001)
    #expect(abs(free.height - 10) < 0.001)
    let square = SelectionGeometry.rect(from: start, to: current, square: true)
    #expect(abs(square.width - 20) < 0.001)
    #expect(abs(square.height - 20) < 0.001)
    let moved = SelectionGeometry.translated(free, by: CGSize(width: 5, height: -3))
    #expect(abs(moved.minX - 15) < 0.001)
    #expect(abs(moved.minY - 7) < 0.001)
    let anchor = SelectionGeometry.resizeAnchor(for: free, mouse: CGPoint(x: 30, y: 20))
    #expect(abs(anchor.x - 10) < 0.001)
    #expect(abs(anchor.y - 10) < 0.001)
}

@Test func focusFrameGeometryCreatesEightClockwiseCornerSegments() {
    let segments = FocusFrameGeometry.cornerSegments(
        in: CGRect(x: 10, y: 20, width: 100, height: 60),
        armLength: 20
    )

    #expect(segments.count == 8)
    #expect(segments[0].start == CGPoint(x: 10, y: 60))
    #expect(segments[0].end == CGPoint(x: 10, y: 80))
    #expect(segments[1].start == CGPoint(x: 10, y: 80))
    #expect(segments[1].end == CGPoint(x: 30, y: 80))
    #expect(segments[6].start == CGPoint(x: 30, y: 20))
    #expect(segments[6].end == CGPoint(x: 10, y: 20))

    #expect(segments.allSatisfy { segment in
        abs(hypot(segment.end.x - segment.start.x, segment.end.y - segment.start.y) - 20) < 0.001
    })
}

@Test func focusFrameGeometryClampsSmallRectArmLength() {
    let segments = FocusFrameGeometry.cornerSegments(
        in: CGRect(x: 0, y: 0, width: 24, height: 10),
        armLength: 20
    )

    #expect(segments.count == 8)
    #expect(segments[0].start == CGPoint(x: 0, y: 5))
    #expect(segments[0].end == CGPoint(x: 0, y: 10))
    #expect(segments[1].end == CGPoint(x: 5, y: 10))
    #expect(segments[2].start == CGPoint(x: 19, y: 10))
    #expect(segments[2].end == CGPoint(x: 24, y: 10))
}

@Test func focusFrameGeometryRejectsInvalidRectsAndArmLengths() {
    #expect(FocusFrameGeometry.cornerSegments(in: .zero).isEmpty)
    #expect(FocusFrameGeometry.cornerSegments(in: .null).isEmpty)
    #expect(FocusFrameGeometry.cornerSegments(in: CGRect(x: 0, y: 0, width: 10, height: 20), armLength: 0).isEmpty)
    #expect(FocusFrameGeometry.cornerSegments(in: CGRect(x: 0, y: 0, width: 10, height: 20), armLength: .nan).isEmpty)
}

@Test func clampedRectStaysInsideDisplayAndPreservesSize() {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let rect = CGRect(x: 1300, y: -40, width: 220, height: 200)
    let clamped = RectMath.clampedRect(rect, in: display)

    #expect(clamped == CGRect(x: 1220, y: 0, width: 220, height: 200))
    #expect(display.contains(clamped))
}

@Test func clampedRectReducesOversizedSelection() {
    let display = CGRect(x: 1920, y: 0, width: 1512, height: 982)
    let clamped = RectMath.clampedRect(
        CGRect(x: 1800, y: -20, width: 1800, height: 1200),
        in: display
    )

    #expect(clamped == display)
    #expect(display.contains(clamped))
}

@Test func translatedSelectionCanBeClampedWithoutChangingItsSize() {
    let display = CGRect(x: 0, y: 0, width: 800, height: 600)
    let selection = CGRect(x: 600, y: 450, width: 160, height: 120)
    let translated = SelectionGeometry.translated(selection, by: CGSize(width: 200, height: 200))
    let clamped = RectMath.clampedRect(translated, in: display)

    #expect(clamped.size == selection.size)
    #expect(clamped.maxX <= display.maxX)
    #expect(clamped.maxY <= display.maxY)
}

@Test func editorLayoutFitsAndClamps() {
    let fitted = EditorLayout.fittedSize(
        imageSize: CGSize(width: 2000, height: 1000),
        in: CGSize(width: 800, height: 600)
    )
    #expect(abs(fitted.width - 800) < 0.001)
    #expect(abs(fitted.height - 400) < 0.001)

    let origin = EditorLayout.clampedOrigin(
        windowSize: CGSize(width: 200, height: 100),
        preferred: CGPoint(x: -40, y: 500),
        visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
        margin: 8
    )
    #expect(abs(origin.x - 8) < 0.001)
    #expect(abs(origin.y - 192) < 0.001)

    let window = EditorLayout.windowSize(
        imageSize: CGSize(width: 100, height: 80),
        chrome: CGSize(width: 20, height: 90),
        minContentWidth: 640,
        maxSize: CGSize(width: 500, height: 400)
    )
    #expect(abs(window.width - 500) < 0.001)
    #expect(abs(window.height - 170) < 0.001)
}

@Test func editorChromePutsToolbarBelowCanvasWithoutOverlap() {
    let bounds = CGSize(width: 800, height: 500)
    let image = CGSize(width: 640, height: 400)
    let toolbar = EditorLayout.toolbarFrame(toolbarSize: CGSize(width: 700, height: 48), in: bounds)
    let canvas = EditorLayout.canvasFrame(imageSize: image, toolbarHeight: toolbar.height, in: bounds)

    #expect(abs(toolbar.minY - EditorLayout.chromePadding) < 0.001)
    #expect(abs(toolbar.height - 48) < 0.001)
    #expect(toolbar.maxY <= canvas.minY)
    #expect(abs(canvas.width - 640) < 0.001)
    #expect(abs(canvas.height - 400) < 0.001)
    #expect(abs(canvas.midX - 400) < 0.001)
    #expect(!canvas.intersects(toolbar))

    let chrome = EditorLayout.chromeSize(toolbarHeight: toolbar.height)
    #expect(abs(chrome.width - EditorLayout.chromePadding * 2) < 0.001)
    #expect(abs(chrome.height - (EditorLayout.chromePadding * 2 + EditorLayout.chromeGap + toolbar.height)) < 0.001)
}

@Test func editorChromeReservesToolbarShadowBleed() {
    #expect(EditorLayout.chromePadding >= EditorLayout.toolbarShadowBleed)
    #expect(EditorLayout.toolbarShadowBleed >= EditorLayout.toolbarShadowRadius)
    #expect(EditorLayout.toolbarShadowBleed >= EditorLayout.toolbarShadowRadius + EditorLayout.toolbarShadowOffsetY)
}

@Test func inPlaceEditorFlipsToolbarOffTheCapture() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let toolbarSize = CGSize(width: 760, height: 52)

    let bottom = CGRect(x: 120, y: 40, width: 220, height: 140)
    let bottomLayout = EditorLayout.inPlace(
        captureRect: bottom,
        toolbarSize: toolbarSize,
        visibleFrame: visible
    )
    let bottomCanvas = bottomLayout.canvasFrame.offsetBy(
        dx: bottomLayout.windowFrame.minX,
        dy: bottomLayout.windowFrame.minY
    )
    let bottomToolbar = bottomLayout.toolbarFrame.offsetBy(
        dx: bottomLayout.windowFrame.minX,
        dy: bottomLayout.windowFrame.minY
    )
    #expect(bottomLayout.toolbarAnchor == .above)
    #expect(bottomLayout.keepsCaptureAligned)
    #expect(abs(bottomCanvas.minX - bottom.minX) < 0.5)
    #expect(abs(bottomCanvas.minY - bottom.minY) < 0.5)
    #expect(!bottomCanvas.intersects(bottomToolbar))
    #expect(bottomToolbar.minY >= visible.minY + 8 - 0.5)
    #expect(bottomToolbar.maxY <= visible.maxY - 8 + 0.5)

    let left = CGRect(x: 0, y: 400, width: 90, height: 70)
    let leftLayout = EditorLayout.inPlace(
        captureRect: left,
        toolbarSize: toolbarSize,
        visibleFrame: visible
    )
    let leftCanvas = leftLayout.canvasFrame.offsetBy(
        dx: leftLayout.windowFrame.minX,
        dy: leftLayout.windowFrame.minY
    )
    let leftToolbar = leftLayout.toolbarFrame.offsetBy(
        dx: leftLayout.windowFrame.minX,
        dy: leftLayout.windowFrame.minY
    )
    #expect(leftLayout.toolbarAnchor == .below)
    #expect(leftLayout.keepsCaptureAligned)
    #expect(abs(leftCanvas.minX - left.minX) < 0.5)
    #expect(!leftCanvas.intersects(leftToolbar))
    #expect(leftToolbar.minX >= visible.minX + 8 - 0.5)
    #expect(leftToolbar.maxX <= visible.maxX - 8 + 0.5)

    let right = CGRect(x: 1400, y: 500, width: 40, height: 50)
    let rightLayout = EditorLayout.inPlace(
        captureRect: right,
        toolbarSize: toolbarSize,
        visibleFrame: visible
    )
    let rightCanvas = rightLayout.canvasFrame.offsetBy(
        dx: rightLayout.windowFrame.minX,
        dy: rightLayout.windowFrame.minY
    )
    let rightToolbar = rightLayout.toolbarFrame.offsetBy(
        dx: rightLayout.windowFrame.minX,
        dy: rightLayout.windowFrame.minY
    )
    #expect(rightLayout.keepsCaptureAligned)
    #expect(abs(rightCanvas.minX - right.minX) < 0.5)
    #expect(!rightCanvas.intersects(rightToolbar))
    #expect(rightToolbar.maxX <= visible.maxX - 8 + 0.5)

    let top = CGRect(x: 200, y: 820, width: 300, height: 80)
    let topLayout = EditorLayout.inPlace(
        captureRect: top,
        toolbarSize: toolbarSize,
        visibleFrame: visible
    )
    let topCanvas = topLayout.canvasFrame.offsetBy(
        dx: topLayout.windowFrame.minX,
        dy: topLayout.windowFrame.minY
    )
    #expect(topLayout.toolbarAnchor == .below)
    #expect(topLayout.keepsCaptureAligned)
    #expect(abs(topCanvas.minY - top.minY) < 0.5)
}

@Test func inPlaceEditorScalesWhenNeitherSideFits() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let capture = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let layout = EditorLayout.inPlace(
        captureRect: capture,
        toolbarSize: CGSize(width: 760, height: 52),
        visibleFrame: visible
    )
    let canvas = layout.canvasFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)
    let toolbar = layout.toolbarFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)
    #expect(!layout.keepsCaptureAligned)
    #expect(layout.imageSize.height < capture.height)
    #expect(!canvas.intersects(toolbar))
    #expect(toolbar.minY >= visible.minY + 8 - 0.5)
    #expect(toolbar.maxY <= visible.maxY - 8 + 0.5)
    #expect(canvas.minY >= visible.minY + 8 - 0.5)
    #expect(canvas.maxY <= visible.maxY - 8 + 0.5)
}

@Test func overlayHUDStaysInsideVisibleBounds() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let hud = CGSize(width: 96, height: 24)

    let below = OverlayChromeLayout.hudFrame(
        size: hud,
        around: CGRect(x: 200, y: 400, width: 320, height: 180),
        in: visible
    )
    #expect(abs(below.maxY - (400 - 8)) < 0.001)
    #expect(below.minY >= visible.minY + 8 - 0.001)

    let bottomEdge = OverlayChromeLayout.hudFrame(
        size: hud,
        around: CGRect(x: 100, y: 40, width: 240, height: 80),
        in: visible
    )
    #expect(bottomEdge.minY >= 40 + 80 + 8 - 0.001)
    #expect(bottomEdge.maxY <= visible.maxY - 8 + 0.001)

    let leftEdge = OverlayChromeLayout.hudFrame(
        size: hud,
        around: CGRect(x: 0, y: 300, width: 40, height: 40),
        in: visible
    )
    #expect(leftEdge.minX >= visible.minX + 8 - 0.001)
    #expect(leftEdge.maxX <= visible.maxX - 8 + 0.001)

    let full = OverlayChromeLayout.hudFrame(
        size: hud,
        around: visible,
        in: visible
    )
    #expect(visible.insetBy(dx: 8, dy: 8).contains(full))
}

@Test func overlayModeSwitchTogglesAreaAndWindow() {
    #expect(OverlayModeSwitch.toggled(from: .area) == .window)
    #expect(OverlayModeSwitch.toggled(from: .window) == .area)
    #expect(OverlayModeSwitch.toggled(from: .other) == nil)
    #expect(OverlayModeSwitch.clickWithoutDragEntersWindow(kind: .area, isDragging: false))
    #expect(!OverlayModeSwitch.clickWithoutDragEntersWindow(kind: .area, isDragging: true))
    #expect(!OverlayModeSwitch.clickWithoutDragEntersWindow(kind: .window, isDragging: false))
    #expect(!OverlayModeSwitch.clickWithoutDragEntersWindow(kind: .other, isDragging: false))
    #expect(OverlayModeSwitch.dragEntersArea(kind: .window, distance: 5))
    #expect(!OverlayModeSwitch.dragEntersArea(kind: .window, distance: OverlayModeSwitch.dragThreshold))
    #expect(!OverlayModeSwitch.dragEntersArea(kind: .area, distance: 20))
    #expect(!OverlayModeSwitch.dragEntersArea(kind: .other, distance: 20))
}

@Test func overlayToggleHotkeyMatchesAndReservesKeys() {
    let space = Hotkey.defaultAreaWindowToggle
    #expect(space.keyCode == 49)
    #expect(space.displayKey == "Space")
    #expect(space.matches(keyCode: 49, modifierRaw: 0))
    let caps = NSEvent.ModifierFlags.capsLock.rawValue
    #expect(space.matches(keyCode: 49, modifierRaw: caps))
    #expect(!space.matches(keyCode: 49, modifierRaw: NSEvent.ModifierFlags.shift.rawValue))
    #expect(!space.isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 53, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 48, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    #expect(Hotkey(keyCode: 36, modifierRaw: 0, character: "").isReservedOverlayShortcut)
    let optionW = Hotkey(
        keyCode: 13,
        modifierRaw: NSEvent.ModifierFlags.option.rawValue,
        character: "w"
    )
    #expect(optionW.matches(keyCode: 13, modifierRaw: NSEvent.ModifierFlags.option.rawValue))
    #expect(!optionW.conflicts(with: space))
}

@Test func hotkeyRejectsSystemScreenshotAndDetectsConflict() {
    let commandShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
    let three = Hotkey(keyCode: 20, modifierRaw: commandShift, character: "3")
    let four = Hotkey(keyCode: 21, modifierRaw: commandShift, character: "4")
    let five = Hotkey(keyCode: 23, modifierRaw: commandShift, character: "5")
    #expect(three.isSystemScreenshotShortcut)
    #expect(four.isSystemScreenshotShortcut)
    #expect(five.isSystemScreenshotShortcut)
    #expect(!Hotkey.defaultAllInOne.isSystemScreenshotShortcut)
    let same = Hotkey(keyCode: 0, modifierRaw: commandShift, character: "a")
    #expect(Hotkey.defaultAllInOne.conflicts(with: same))
    #expect(!Hotkey.defaultAllInOne.conflicts(with: three))
}

@Test func capturePhaseMachineTransitions() {
    var machine = CapturePhaseMachine()
    #expect(machine.phase == .idle)
    #expect(!machine.isBusy)
    machine.startCapture()
    #expect(machine.phase == .capturing)
    #expect(machine.isBusy)
    machine.startEditing()
    #expect(machine.phase == .editing)
    machine.reset()
    #expect(machine.phase == .idle)
    machine.startCapture()
    machine.reset()
    #expect(machine.phase == .idle)
}

@Test func windowInclusionFiltersLayerSizeAndPID() {
    let our: pid_t = 100
    #expect(WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 80, height: 80), processID: our, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 0, size: CGSize(width: 20, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: -1, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
    #expect(!WindowInclusion.shouldInclude(layer: 25, size: CGSize(width: 80, height: 80), processID: 200, ourPID: our))
}

@Test func windowHitTestingFrontmostAndCycle() {
    let front = CGRect(x: 100, y: 100, width: 200, height: 120)
    let back = CGRect(x: 80, y: 80, width: 400, height: 300)
    let miss = CGRect(x: 0, y: 0, width: 40, height: 40)
    let hits = WindowHitTesting.containing(CGPoint(x: 150, y: 150), in: [front, back, miss])
    #expect(hits == [0, 1])
    #expect(WindowHitTesting.cycledIndex(current: 0, count: 2, reverse: false) == 1)
    #expect(WindowHitTesting.cycledIndex(current: 1, count: 2, reverse: false) == 0)
    #expect(WindowHitTesting.cycledIndex(current: 0, count: 2, reverse: true) == 1)
}

@Test func annotationUndoStackAndCounter() {
    #expect(AnnotationMath.nextCounter(existing: []) == 1)
    #expect(AnnotationMath.nextCounter(existing: [1, 3, 2]) == 4)
    #expect(AnnotationMath.isSignificantRect(CGRect(x: 0, y: 0, width: 4, height: 4)))
    #expect(!AnnotationMath.isSignificantRect(CGRect(x: 0, y: 0, width: 2, height: 8)))
    #expect(AnnotationMath.isSignificantDistance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)))

    var stack = UndoStack<Int>()
    stack.append(1)
    stack.append(2)
    #expect(stack.items == [1, 2])
    #expect(stack.canUndo)
    stack.undo()
    #expect(stack.items == [1])
    #expect(stack.canRedo)
    stack.redo()
    #expect(stack.items == [1, 2])
    stack.undo()
    stack.append(9)
    #expect(stack.items == [1, 9])
    #expect(!stack.canRedo)
}

@Test func annotationFontSizeScalesWithStroke() {
    #expect(abs(AnnotationMath.fontSize(lineWidth: 2) - 24) < 0.001)
    #expect(abs(AnnotationMath.fontSize(lineWidth: 4) - 32) < 0.001)
    #expect(abs(AnnotationMath.fontSize(lineWidth: 8) - 48) < 0.001)
    #expect(AnnotationMath.strokePresets == [2, 4, 8])
}

@Test func annotationShiftSnapsSquareAndDiagonals() {
    let square = SelectionGeometry.rect(
        from: CGPoint(x: 10, y: 10),
        to: CGPoint(x: 30, y: 20),
        square: true
    )
    #expect(abs(square.width - 20) < 0.001)
    #expect(abs(square.height - 20) < 0.001)

    let horizontal = AnnotationMath.snappedEndpoint(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 40, y: 3)
    )
    #expect(abs(horizontal.x - 40) < 0.2)
    #expect(abs(horizontal.y) < 0.2)

    let diagonal = AnnotationMath.snappedEndpoint(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 10, y: 9)
    )
    #expect(abs(diagonal.x - diagonal.y) < 0.001)
    #expect(abs(hypot(diagonal.x, diagonal.y) - hypot(10, 9)) < 0.001)
}
