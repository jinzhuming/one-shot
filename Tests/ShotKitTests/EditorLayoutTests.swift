import AppKit
import Testing
@testable import ShotKit

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

@Test func canvasZoomClampsMagnificationAndFitsImageToViewport() {
    #expect(CanvasZoom.clamped(0.01) == CanvasZoom.minimumMagnification)
    #expect(CanvasZoom.clamped(8) == CanvasZoom.maximumMagnification)
    #expect(CanvasZoom.clamped(.nan) == 1)

    let fitted = CanvasZoom.fittedMagnification(
        imageSize: CGSize(width: 1600, height: 900),
        viewportSize: CGSize(width: 800, height: 700)
    )
    #expect(abs(fitted - 0.5) < 0.001)
}

@Test func canvasZoomSeparatesTrackpadPanFromMouseZoom() {
    #expect(CanvasZoom.scrollAction(
        hasPreciseScrollingDeltas: true,
        commandPressed: false,
        commandScrollEnabled: false
    ) == .pan)
    #expect(CanvasZoom.scrollAction(
        hasPreciseScrollingDeltas: false,
        commandPressed: false,
        commandScrollEnabled: false
    ) == .zoom)
    #expect(CanvasZoom.scrollAction(
        hasPreciseScrollingDeltas: true,
        commandPressed: true,
        commandScrollEnabled: true
    ) == .zoom)
    #expect(CanvasZoom.scrollAction(
        hasPreciseScrollingDeltas: true,
        commandPressed: true,
        commandScrollEnabled: false
    ) == .pan)
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

@Test func centeredEditorKeepsCanvasAndToolbarInsideVisibleFrame() {
    let visible = CGRect(x: 120, y: 40, width: 1440, height: 860)
    let arrangement = EditorLayout.centered(
        imageSize: CGSize(width: 640, height: 400),
        toolbarSize: CGSize(width: 760, height: 52),
        visibleFrame: visible
    )
    let canvas = arrangement.canvasFrame.offsetBy(
        dx: arrangement.windowFrame.minX,
        dy: arrangement.windowFrame.minY
    )
    let toolbar = arrangement.toolbarFrame.offsetBy(
        dx: arrangement.windowFrame.minX,
        dy: arrangement.windowFrame.minY
    )

    #expect(!arrangement.keepsCaptureAligned)
    #expect(arrangement.windowFrame.minX >= visible.minX + 8 - 0.5)
    #expect(arrangement.windowFrame.maxX <= visible.maxX - 8 + 0.5)
    #expect(arrangement.windowFrame.minY >= visible.minY + 8 - 0.5)
    #expect(arrangement.windowFrame.maxY <= visible.maxY - 8 + 0.5)
    #expect(abs(arrangement.windowFrame.midX - visible.midX) < 0.5)
    #expect(abs(arrangement.windowFrame.midY - visible.midY) < 0.5)
    #expect(toolbar.maxY <= canvas.minY)
    #expect(!canvas.intersects(toolbar))
}

@Test func windowedEditorDocksToolbarAboveCanvasAndPreservesImageBounds() {
    let contentSize = EditorLayout.windowedInitialContentSize(
        imageSize: CGSize(width: 640, height: 400),
        toolbarSize: CGSize(width: 800, height: 84),
        maxContentSize: CGSize(width: 1440, height: 860)
    )
    let layout = EditorLayout.windowed(
        imageSize: CGSize(width: 640, height: 400),
        toolbarSize: CGSize(width: 800, height: 84),
        contentSize: contentSize
    )

    #expect(layout.contentSize == contentSize)
    #expect(abs(layout.toolbarFrame.maxY - layout.contentSize.height) < 0.001)
    #expect(abs(layout.toolbarFrame.minX) < 0.001)
    #expect(abs(layout.toolbarFrame.width - layout.contentSize.width) < 0.001)
    #expect(layout.canvasFrame.maxY <= layout.toolbarFrame.minY)
    #expect(!layout.toolbarFrame.intersects(layout.canvasFrame))
    #expect(layout.canvasFrame.width == 640)
    #expect(layout.canvasFrame.height == 400)
    #expect(layout.canvasFrame.minX >= EditorLayout.windowedWorkspacePadding)
    #expect(layout.canvasFrame.maxX <= contentSize.width - EditorLayout.windowedWorkspacePadding)
    #expect(layout.canvasFrame.minY >= EditorLayout.windowedWorkspacePadding)
    #expect(layout.canvasFrame.maxY <= layout.toolbarFrame.minY - EditorLayout.windowedWorkspacePadding)
}

@Test func windowedEditorResizesCanvasWithoutUpscalingOrLeavingWorkspace() {
    let compact = EditorLayout.windowed(
        imageSize: CGSize(width: 1200, height: 800),
        toolbarSize: CGSize(width: 760, height: 84),
        contentSize: CGSize(width: 900, height: 520)
    )
    let resized = EditorLayout.windowed(
        imageSize: CGSize(width: 1200, height: 800),
        toolbarSize: CGSize(width: 760, height: 84),
        contentSize: CGSize(width: 1440, height: 900)
    )

    #expect(compact.imageSize.width < 1200)
    #expect(compact.imageSize.height < 800)
    #expect(resized.imageSize.width <= 1200)
    #expect(resized.imageSize.height <= 800)
    #expect(compact.canvasFrame.minX >= EditorLayout.windowedWorkspacePadding - 0.5)
    #expect(compact.canvasFrame.minY >= EditorLayout.windowedWorkspacePadding - 0.5)
    #expect(compact.canvasFrame.maxX <= compact.contentSize.width - EditorLayout.windowedWorkspacePadding + 0.5)
    #expect(compact.canvasFrame.maxY <= compact.toolbarFrame.minY - EditorLayout.windowedToolbarGap - EditorLayout.windowedWorkspacePadding + 0.5)
    #expect(resized.canvasFrame.width > compact.canvasFrame.width)
}

@Test func windowedEditorInitialSizeClampsToSmallDisplayAndToolbar() {
    let size = EditorLayout.windowedInitialContentSize(
        imageSize: CGSize(width: 1600, height: 1000),
        toolbarSize: CGSize(width: 900, height: 84),
        maxContentSize: CGSize(width: 640, height: 480)
    )

    #expect(size.width == 640)
    #expect(size.height == 480)
    let layout = EditorLayout.windowed(
        imageSize: CGSize(width: 1600, height: 1000),
        toolbarSize: CGSize(width: 900, height: 84),
        contentSize: size
    )
    #expect(layout.canvasFrame.minX >= 0)
    #expect(layout.canvasFrame.minY >= 0)
    #expect(layout.canvasFrame.maxX <= size.width)
    #expect(layout.canvasFrame.maxY <= layout.toolbarFrame.minY)
    #expect(abs(layout.toolbarFrame.maxY - size.height) < 0.001)
    #expect(abs(layout.toolbarFrame.width - size.width) < 0.001)
}

@Test func windowedEditorMinimumWidthFollowsToolbarForSmallImage() {
    let size = EditorLayout.windowedInitialContentSize(
        imageSize: CGSize(width: 240, height: 140),
        toolbarSize: CGSize(width: 900, height: 84),
        maxContentSize: CGSize(width: 1440, height: 900)
    )

    #expect(size.width == 900)
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

@Test func inPlaceEditorClampsCaptureOutsideVisibleFrame() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let capture = CGRect(x: -240, y: 400, width: 480, height: 300)
    let layout = EditorLayout.inPlace(
        captureRect: capture,
        toolbarSize: CGSize(width: 760, height: 52),
        visibleFrame: visible
    )
    let canvas = layout.canvasFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)
    let toolbar = layout.toolbarFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)

    #expect(!layout.keepsCaptureAligned)
    #expect(canvas.minX >= visible.minX + 8 - 0.5)
    #expect(canvas.maxX <= visible.maxX - 8 + 0.5)
    #expect(canvas.minY >= visible.minY + 8 - 0.5)
    #expect(canvas.maxY <= visible.maxY - 8 + 0.5)
    #expect(!canvas.intersects(toolbar))
}

@Test func inPlaceEditorFallsBackWhenToolbarCannotFitDisplayWidth() {
    let visible = CGRect(x: 0, y: 0, width: 640, height: 480)
    let layout = EditorLayout.inPlace(
        captureRect: CGRect(x: 120, y: 180, width: 200, height: 120),
        toolbarSize: CGSize(width: 760, height: 52),
        visibleFrame: visible
    )
    let canvas = layout.canvasFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)
    let toolbar = layout.toolbarFrame.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY)

    #expect(!layout.keepsCaptureAligned)
    #expect(visible.insetBy(dx: 8, dy: 8).contains(layout.windowFrame))
    #expect(visible.insetBy(dx: 8, dy: 8).contains(canvas))
    #expect(visible.insetBy(dx: 8, dy: 8).contains(toolbar))
    #expect(!canvas.intersects(toolbar))
}
