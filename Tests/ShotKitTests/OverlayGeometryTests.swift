import AppKit
import Testing
@testable import ShotKit

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

@Test func magnifierFramePrefersVisibleSpaceAndClampsToScreen() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let size = CGSize(width: 124, height: 124)

    let lowerRight = MagnifierLayout.frame(
        cursor: CGPoint(x: 720, y: 400),
        size: size,
        visibleFrame: visible
    )
    #expect(lowerRight.minX > 720)
    #expect(lowerRight.maxY < 400)
    #expect(visible.insetBy(dx: 8, dy: 8).contains(lowerRight))

    let top = MagnifierLayout.frame(
        cursor: CGPoint(x: 20, y: 890),
        size: size,
        visibleFrame: visible
    )
    #expect(visible.insetBy(dx: 8, dy: 8).contains(top))
    #expect(top.minX >= visible.minX + 8)
}

@Test func magnifierFrameKeepsPointerAsAnchorNearEdges() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let frame = MagnifierLayout.frame(
        cursor: CGPoint(x: 1420, y: 60),
        visibleFrame: visible
    )

    #expect(visible.insetBy(dx: 8, dy: 8).contains(frame))
    #expect(frame.maxX < 1420)
    #expect(frame.minY > 60)
}

@Test func magnifierFrameKeepsChromeInsideSafeAreaAndContentAligned() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let contentSize = CGSize(width: 124, height: 124)
    let outer = MagnifierLayout.frame(
        cursor: CGPoint(x: 720, y: 400),
        size: contentSize,
        visibleFrame: visible
    )
    let content = MagnifierLayout.contentFrame(for: outer)

    #expect(visible.insetBy(dx: 8, dy: 8).contains(outer))
    #expect(abs(content.width - contentSize.width) < 0.001)
    #expect(abs(content.height - contentSize.height) < 0.001)
    #expect(abs(outer.midX - content.midX) < 0.001)
    #expect(abs(outer.midY - content.midY) < 0.001)
    #expect(abs(outer.width - content.width - MagnifierLayout.defaultChromeInset * 2) < 0.001)
}

@Test func magnifierFrameStaysOutsideSelectionAtItsLowerRightCorner() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let selection = CGRect(x: 320, y: 420, width: 360, height: 220)
    let frame = MagnifierLayout.frame(
        nextTo: selection,
        visibleFrame: visible
    )

    #expect(!frame.isEmpty)
    #expect(!frame.intersects(selection))
    #expect(abs(frame.maxX - selection.maxX) < 0.001)
    #expect(frame.maxY < selection.minY)
    #expect(visible.insetBy(dx: 8, dy: 8).contains(frame))
}

@Test func magnifierFrameUsesAnotherSideWhenLowerRightSpaceIsUnavailable() {
    let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    let selection = CGRect(x: 1180, y: 60, width: 220, height: 500)
    let frame = MagnifierLayout.frame(
        nextTo: selection,
        visibleFrame: visible
    )

    #expect(!frame.isEmpty)
    #expect(!frame.intersects(selection))
    #expect(visible.insetBy(dx: 8, dy: 8).contains(frame))
}

@Test func magnifierSourceRectPreservesLensAspectAndZoom() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let source = MagnifierLayout.sourceRect(
        cursor: CGPoint(x: 720, y: 450),
        imageBounds: bounds,
        destinationSize: CGSize(width: 124, height: 124),
        zoom: 8
    )
    #expect(bounds.contains(source))
    #expect(abs(source.width - 15.5) < 0.001)
    #expect(abs(source.height - 15.5) < 0.001)
    #expect(abs(source.width / source.height - 1) < 0.001)
}

@Test func magnifierSourceRectPreservesNonSquareLensAspectAtEdge() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let destination = CGSize(width: 160, height: 100)
    let source = MagnifierLayout.sourceRect(
        cursor: CGPoint(x: 0, y: 900),
        imageBounds: bounds,
        destinationSize: destination,
        zoom: 8
    )

    #expect(bounds.contains(source))
    #expect(abs(source.width / source.height - destination.width / destination.height) < 0.001)
    #expect(source.minX == bounds.minX)
    #expect(source.maxY == bounds.maxY)
}

@Test func magnifierCursorPositionFollowsClampedSourceRect() {
    let destination = CGRect(x: 100, y: 200, width: 124, height: 124)
    let source = CGRect(x: 0, y: 0, width: 16, height: 16)

    let center = MagnifierLayout.cursorPosition(
        cursor: CGPoint(x: 8, y: 8),
        sourceRect: source,
        destinationFrame: destination
    )
    #expect(center == CGPoint(x: 162, y: 262))

    let edge = MagnifierLayout.cursorPosition(
        cursor: CGPoint(x: 0, y: 16),
        sourceRect: source,
        destinationFrame: destination
    )
    #expect(edge == CGPoint(x: destination.minX, y: destination.maxY))
}

@Test func overlayFocusStyleUsesLighterIdleMaskAndFocusedMask() {
    #expect(OverlayFocusStyle.maskOpacity(
        dimOnly: false,
        hasFocus: false,
        reduceTransparency: false
    ) == OverlayFocusStyle.idleMaskOpacity)
    #expect(OverlayFocusStyle.maskOpacity(
        dimOnly: false,
        hasFocus: true,
        reduceTransparency: false
    ) == OverlayFocusStyle.focusedMaskOpacity)
    #expect(OverlayFocusStyle.focusedMaskOpacity > OverlayFocusStyle.idleMaskOpacity)
}

@Test func overlayFocusStylePrioritizesAccessibilityAndDimOnlyModes() {
    #expect(OverlayFocusStyle.maskOpacity(
        dimOnly: true,
        hasFocus: false,
        reduceTransparency: false
    ) == OverlayFocusStyle.dimOnlyMaskOpacity)
    #expect(OverlayFocusStyle.maskOpacity(
        dimOnly: false,
        hasFocus: true,
        reduceTransparency: true
    ) == OverlayFocusStyle.reducedTransparencyMaskOpacity)
    #expect(OverlayFocusStyle.reducedTransparencyMaskOpacity > OverlayFocusStyle.focusedMaskOpacity)
}

@Test func overlayFocusStyleAddsSubtleWindowHighlight() {
    #expect(OverlayFocusStyle.windowHighlightOpacity > 0)
    #expect(OverlayFocusStyle.windowHighlightOpacity <= 0.1)
    #expect(OverlayFocusStyle.windowHighlightOpacity(reduceTransparency: false)
        == OverlayFocusStyle.windowHighlightOpacity)
    #expect(OverlayFocusStyle.windowHighlightOpacity(reduceTransparency: true)
        == OverlayFocusStyle.reducedTransparencyWindowHighlightOpacity)
    #expect(OverlayFocusStyle.reducedTransparencyWindowHighlightOpacity
        > OverlayFocusStyle.windowHighlightOpacity)
}

@Test func overlayFocusStyleUsesRestrainedSelectionAndMagnifierChrome() {
    #expect(OverlayFocusStyle.selectionDashLength > 0)
    #expect(OverlayFocusStyle.selectionDashGap > 0)
    #expect(OverlayFocusStyle.selectionHandleDiameter < 8)
    #expect(OverlayFocusStyle.selectionBorderOpacity < 0.8)
    #expect(OverlayFocusStyle.magnifierBorderLineWidth == 1)
    #expect(OverlayFocusStyle.magnifierBezelOpacity > 0.8)
}
