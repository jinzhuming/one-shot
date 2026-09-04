import AppKit
import ShotKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func selectNextKeyView(_ sender: Any?) {}
    override func selectPreviousKeyView(_ sender: Any?) {}
}

struct OverlayVisualState: Equatable {
    var highlightedWindow: CapturableWindow?
    var selectionRect: CGRect?
    var dimOnly = false
    var holeIsWindow = false
}

@MainActor
protocol SelectionOverlayDelegate: AnyObject {
    func overlayMouseMoved(_ pointInScreen: CGPoint)
    func overlayMouseDown(_ pointInScreen: CGPoint)
    func overlayMouseDragged(_ pointInScreen: CGPoint)
    func overlayMouseUp(_ pointInScreen: CGPoint)
    func overlayKeyDown(_ event: NSEvent)
    func overlayFlagsChanged(_ event: NSEvent)
}

final class SelectionOverlayView: NSView {
    weak var delegate: SelectionOverlayDelegate?
    var backgroundImage: NSImage? {
        didSet { needsDisplay = true }
    }
    var visual = OverlayVisualState() {
        didSet {
            guard oldValue != visual else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role { .layoutArea }
    override func accessibilityLabel() -> String? { String(localized: "截图选区") }
    override func accessibilityHelp() -> String? {
        let key = AppSettings.shared.areaWindowToggleHotkey.localizedDisplayString
        return String(localized: "拖拽框选区域，或点击切换窗口。\(key) 在区域和窗口之间切换。Tab 切换重叠窗口。按 Esc 取消。")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        if let backgroundImage {
            backgroundImage.draw(
                in: bounds,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: isFlipped,
                hints: nil
            )
        } else {
            NSColor.clear.setFill()
            dirtyRect.fill(using: .copy)
        }
        NSGraphicsContext.restoreGraphicsState()

        let hole = holeRectInView()
        let radius = visual.holeIsWindow ? 6.0 : 2.0
        let overlay = NSBezierPath(rect: bounds)
        if let hole {
            overlay.append(NSBezierPath(roundedRect: hole, xRadius: radius, yRadius: radius))
            overlay.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(visual.dimOnly ? 0.45 : 0.55).setFill()
        overlay.fill()

        if let hole {
            drawHighlight(around: hole, radius: radius, isWindow: visual.holeIsWindow)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        delegate?.overlayMouseMoved(screenPoint(from: event))
    }

    override func mouseMoved(with event: NSEvent) {
        delegate?.overlayMouseMoved(screenPoint(from: event))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        delegate?.overlayMouseDown(screenPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.overlayMouseDragged(screenPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.overlayMouseUp(screenPoint(from: event))
    }

    override func keyDown(with event: NSEvent) {
        delegate?.overlayKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        delegate?.overlayKeyDown(event)
    }

    override func flagsChanged(with event: NSEvent) {
        delegate?.overlayFlagsChanged(event)
    }

    private func screenPoint(from event: NSEvent) -> CGPoint {
        window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin ?? event.locationInWindow
    }

    private func drawHighlight(around hole: CGRect, radius: CGFloat, isWindow: Bool) {
        let accent = NSColor.controlAccentColor
        if isWindow {
            let glow = NSBezierPath(roundedRect: hole.insetBy(dx: -3, dy: -3), xRadius: radius + 3, yRadius: radius + 3)
            glow.lineWidth = 8
            accent.withAlphaComponent(0.35).setStroke()
            glow.stroke()

            let border = NSBezierPath(
                roundedRect: hole.insetBy(dx: -1, dy: -1),
                xRadius: radius + 1,
                yRadius: radius + 1
            )
            border.lineWidth = 3
            accent.setStroke()
            border.stroke()
            return
        }

        let frameRect = hole.insetBy(dx: -1, dy: -1)
        let segments = FocusFrameGeometry.cornerSegments(in: frameRect)
        guard !segments.isEmpty else { return }

        let contrast = NSBezierPath()
        let focus = NSBezierPath()
        for segment in segments {
            contrast.move(to: segment.start)
            contrast.line(to: segment.end)
            focus.move(to: segment.start)
            focus.line(to: segment.end)
        }

        contrast.lineWidth = 4
        contrast.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.7).setStroke()
        contrast.stroke()

        focus.lineWidth = 2
        focus.lineCapStyle = .round
        accent.setStroke()
        focus.stroke()
    }

    private func holeRectInView() -> CGRect? {
        let global: CGRect?
        if let selection = visual.selectionRect, selection.width > 2, selection.height > 2 {
            global = selection
        } else {
            global = visual.highlightedWindow?.frame
        }
        guard let global, let window else { return nil }
        let inWindow = window.convertFromScreen(global)
        let local = convert(inWindow, from: nil).intersection(bounds.insetBy(dx: -2, dy: -2))
        guard !local.isNull, !local.isEmpty, local.width > 1, local.height > 1 else { return nil }
        return local
    }
}
