import AppKit

/// The mode bar must receive mouse clicks without taking keyboard focus away
/// from the capture overlay. Keyboard events are routed by OverlayController.
final class CaptureModeBarWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
