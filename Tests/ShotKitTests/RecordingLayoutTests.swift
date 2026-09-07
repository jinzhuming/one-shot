import AppKit
import Testing
@testable import ShotKit

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

@Test func recordingIndicatorBadgePrefersSpaceAboveTargetAndAvoidsControlBar() {
    let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let target = CGRect(x: 420, y: 360, width: 320, height: 180)
    let badge = RecordingIndicatorLayout.badgeFrame(
        size: CGSize(width: 140, height: 26),
        targetRect: target,
        visibleFrame: visible,
        reservedFrame: CGRect(x: 490, y: 68, width: 420, height: 58)
    )

    #expect(abs(badge.midX - target.midX) < 0.001)
    #expect(abs(badge.minY - target.maxY - 8) < 0.001)
    #expect(visible.insetBy(dx: 8, dy: 8).contains(badge))
    #expect(!badge.intersects(CGRect(x: 490, y: 68, width: 420, height: 58)))
}

@Test func recordingIndicatorBadgeFlipsBelowTopEdgeAndClampsEdgeTargets() {
    let visible = CGRect(x: 1920, y: 40, width: 1512, height: 982)
    let topTarget = CGRect(x: 2200, y: 900, width: 260, height: 100)
    let topBadge = RecordingIndicatorLayout.badgeFrame(
        size: CGSize(width: 140, height: 26),
        targetRect: topTarget,
        visibleFrame: visible
    )
    #expect(topBadge.maxY <= topTarget.minY - 8 + 0.001)
    #expect(visible.insetBy(dx: 8, dy: 8).contains(topBadge))

    let edgeTarget = CGRect(x: 1920, y: 40, width: 80, height: 80)
    let edgeBadge = RecordingIndicatorLayout.badgeFrame(
        size: CGSize(width: 140, height: 26),
        targetRect: edgeTarget,
        visibleFrame: visible
    )
    #expect(visible.insetBy(dx: 8, dy: 8).contains(edgeBadge))
}

@Test func recordingIndicatorBadgeUsesVisibleCornerForFullscreen() {
    let visible = CGRect(x: 0, y: 24, width: 1440, height: 876)
    let badge = RecordingIndicatorLayout.badgeFrame(
        size: CGSize(width: 140, height: 26),
        targetRect: nil,
        visibleFrame: visible
    )

    #expect(badge.maxX <= visible.maxX - 8 + 0.001)
    #expect(badge.maxY <= visible.maxY - 8 + 0.001)
    #expect(badge.minX > visible.midX)
}

@Test func recordingLayoutFormatsElapsedDuration() {
    #expect(RecordingLayout.formattedDuration(65.9) == "01:05")
    #expect(RecordingLayout.formattedDuration(-1) == "00:00")
}
