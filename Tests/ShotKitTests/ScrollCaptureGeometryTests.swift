import CoreGraphics
import Testing
@testable import ShotKit

@Test func scrollCaptureGeometryComputesAdvanceAndStrip() {
    #expect(ScrollCaptureGeometry.advance(viewportHeight: 100, overlap: 40) == 60)
    #expect(ScrollCaptureGeometry.advance(viewportHeight: 100, overlap: 0) == nil)
    #expect(ScrollCaptureGeometry.advance(viewportHeight: 100, overlap: 100) == nil)

    #expect(
        ScrollCaptureGeometry.newStripRect(
            direction: .down,
            viewportSize: CGSize(width: 200, height: 100),
            overlap: 40
        ) == CGRect(x: 0, y: 40, width: 200, height: 60)
    )
    #expect(
        ScrollCaptureGeometry.newStripRect(
            direction: .up,
            viewportSize: CGSize(width: 200, height: 100),
            overlap: 40
        ) == CGRect(x: 0, y: 0, width: 200, height: 60)
    )
}

@Test func scrollCaptureGeometryShiftsExistingContentWhenScrollingUp() {
    #expect(ScrollCaptureGeometry.shiftedTop(direction: .down, existingTop: 80, newStripHeight: 20) == 80)
    #expect(ScrollCaptureGeometry.shiftedTop(direction: .up, existingTop: 80, newStripHeight: 20) == 100)
}
