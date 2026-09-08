import AppKit
import SwiftUI

/// Capture chrome is hosted in separate nonactivating windows. Without an
/// explicit cursor rect, the full-screen selection view can leave its
/// crosshair cursor active while the pointer is over a button.
final class CaptureChromeHostingView<Content: View>: NSHostingView<Content> {
    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let cursorTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(cursorTrackingArea)
        self.cursorTrackingArea = cursorTrackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

/// The mode bar must receive mouse clicks without taking keyboard focus away
/// from the capture overlay. Keyboard events are routed by OverlayController.
final class CaptureModeBarWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
