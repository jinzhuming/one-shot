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

@Test func cocoaRectFlipsFromCGWindowOrigin() {
    let cg = CGRect(x: 100, y: 50, width: 400, height: 300)
    let cocoa = RectMath.cocoaRect(fromCGWindowBounds: cg, primaryHeight: 982)
    #expect(abs(cocoa.origin.x - 100) < 0.001)
    #expect(abs(cocoa.origin.y - 632) < 0.001)
    #expect(cocoa.size == cg.size)
}

@Test func cocoaRectPreservesVerticalDisplayOffset() {
    let cg = CGRect(x: 1920, y: 900, width: 800, height: 300)
    let cocoa = RectMath.cocoaRect(fromCGWindowBounds: cg, primaryHeight: 1080)
    #expect(cocoa == CGRect(x: 1920, y: -120, width: 800, height: 300))
}

@Test func cocoaRectHandlesDisplaysOnEverySideOfPrimary() {
    let primaryHeight: CGFloat = 1080
    let cocoaRects = [
        CGRect(x: -1200, y: 160, width: 800, height: 500),
        CGRect(x: 2080, y: 120, width: 800, height: 500),
        CGRect(x: 240, y: 1240, width: 800, height: 500),
        CGRect(x: 240, y: -760, width: 800, height: 500)
    ]

    for cocoa in cocoaRects {
        let cg = CGRect(
            x: cocoa.minX,
            y: primaryHeight - cocoa.minY - cocoa.height,
            width: cocoa.width,
            height: cocoa.height
        )
        #expect(RectMath.cocoaRect(fromCGWindowBounds: cg, primaryHeight: primaryHeight) == cocoa)
    }
}

@Test func largestIntersectionSelectsTheCorrectDisplayArrangement() {
    let frames = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -1280, y: 0, width: 1280, height: 1024),
        CGRect(x: 1920, y: 120, width: 1440, height: 900),
        CGRect(x: 0, y: 1080, width: 1920, height: 1200),
        CGRect(x: 0, y: -900, width: 1600, height: 900)
    ]

    #expect(RectMath.largestIntersectionIndex(
        of: CGRect(x: -1000, y: 100, width: 600, height: 500),
        in: frames
    ) == 1)
    #expect(RectMath.largestIntersectionIndex(
        of: CGRect(x: 1800, y: 300, width: 500, height: 500),
        in: frames
    ) == 2)
    #expect(RectMath.largestIntersectionIndex(
        of: CGRect(x: 200, y: 1000, width: 800, height: 600),
        in: frames
    ) == 3)
    #expect(RectMath.largestIntersectionIndex(
        of: CGRect(x: 200, y: -700, width: 800, height: 500),
        in: frames
    ) == 4)
    #expect(RectMath.largestIntersectionIndex(
        of: CGRect(x: 5000, y: 5000, width: 100, height: 100),
        in: frames
    ) == nil)
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
