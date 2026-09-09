import CoreGraphics
import Testing
@testable import ShotKit

@Test func transientPanelsFitNegativeOriginDisplaysAndLongContent() {
    let display = CGRect(x: -1280, y: -240, width: 640, height: 480)
    for trailing in [false, true] {
        let frame = InterfaceLayout.bottomFrame(size: CGSize(width: 1200, height: 720),
                                              in: display, trailing: trailing)
        #expect(display.insetBy(dx: 16, dy: 16).contains(frame))
        #expect(frame.width == 608)
        #expect(frame.height == 448)
    }
    #expect(InterfaceLayout.toolbarWidth(available: 584) == 584)
    #expect(InterfaceLayout.toolbarWidth(available: 1200) == 820)
}

@Test func recordingPreviewsRemainReachableWhenAllColumnsAreFull() {
    let display = CGRect(x: -640, y: 40, width: 640, height: 480)
    let frames = RecordingLayout.previewFrames(count: 12, windowSize: CGSize(width: 380, height: 284), visibleFrame: display)
    #expect(frames.count == 12)
    #expect(frames.allSatisfy { display.insetBy(dx: 16, dy: 16).contains($0) })
}
