import AppKit
import QuartzCore
import ShotKit

final class OverlayWindow: NSWindow {
    var onRequestCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func selectNextKeyView(_ sender: Any?) {}
    override func selectPreviousKeyView(_ sender: Any?) {}

    // Keep Escape working even if AppKit routes the cancel operation directly
    // to the window instead of the overlay view (for example after a focus
    // change or while a custom field editor is active).
    override func cancelOperation(_ sender: Any?) {
        onRequestCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
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
    var magnifierFrame: CGRect? {
        didSet { needsDisplay = true }
    }
    var magnifierSourceRect: CGRect? {
        didSet { needsDisplay = true }
    }
    var magnifierCursor: CGPoint? {
        didSet { needsDisplay = true }
    }
    var visual = OverlayVisualState() {
        didSet {
            guard oldValue != visual else { return }
            needsDisplay = true
            animateMaskOpacity()
        }
    }

    private var maskOpacity: CGFloat = OverlayFocusStyle.idleMaskOpacity
    private var maskAnimationTimer: Timer?

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

    deinit {
        maskAnimationTimer?.invalidate()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role { .layoutArea }
    override func accessibilityLabel() -> String? { String(localized: "截图选区") }
    override func accessibilityHelp() -> String? {
        let key = AppSettings.shared.areaWindowToggleHotkey.localizedDisplayString
        return String(localized: "拖拽框选区域，Shift 保持等比例，空格移动选区。\(key) 在区域和窗口之间切换。Tab 切换重叠窗口。按 Esc 取消。")
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
        NSColor.black.withAlphaComponent(maskOpacity).setFill()
        overlay.fill()

        if let hole {
            if visual.holeIsWindow {
                drawWindowHighlight(inside: hole, radius: radius)
            }
            drawHighlight(around: hole, radius: radius, isWindow: visual.holeIsWindow)
        }
        drawMagnifier()
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
        guard !isWindow else { return }
        let accent = NSColor.controlAccentColor

        let frameRect = hole.insetBy(dx: -1, dy: -1)
        let border = NSBezierPath(roundedRect: frameRect, xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        accent.withAlphaComponent(0.72).setStroke()
        border.stroke()

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

    private func drawWindowHighlight(inside hole: CGRect, radius: CGFloat) {
        // Window capture is a hover/focus state, not a filled selection. Keep
        // the tint quiet so the window's content remains the visual anchor.
        let highlight = NSBezierPath(
            roundedRect: hole.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(0, radius - 0.5),
            yRadius: max(0, radius - 0.5)
        )
        let opacity = OverlayFocusStyle.windowHighlightOpacity(
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
        NSColor.controlAccentColor.withAlphaComponent(opacity).setFill()
        highlight.fill()

        // A neutral contrast keyline keeps the accent ring readable over both
        // bright and dark window contents. This is intentionally a crisp ring
        // instead of a large glow, matching native macOS focus treatment.
        let contrast = NSBezierPath(
            roundedRect: hole.insetBy(dx: -1, dy: -1),
            xRadius: radius + 1,
            yRadius: radius + 1
        )
        contrast.lineWidth = 4
        NSColor.black.withAlphaComponent(0.72).setStroke()
        contrast.stroke()

        let border = NSBezierPath(
            roundedRect: hole.insetBy(dx: -0.5, dy: -0.5),
            xRadius: radius + 0.5,
            yRadius: radius + 0.5
        )
        border.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        border.stroke()
    }

    private func animateMaskOpacity() {
        let hasFocus = visual.selectionRect != nil || visual.highlightedWindow != nil
        let target = OverlayFocusStyle.maskOpacity(
            dimOnly: visual.dimOnly,
            hasFocus: hasFocus,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
        guard abs(target - maskOpacity) > 0.001 else { return }

        maskAnimationTimer?.invalidate()
        let start = maskOpacity
        let startTime = CACurrentMediaTime()
        let duration = 0.12
        maskAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let progress = min(1, (CACurrentMediaTime() - startTime) / duration)
            let eased = 1 - pow(1 - progress, 3)
            self.maskOpacity = start + (target - start) * eased
            self.needsDisplay = true

            if progress >= 1 {
                self.maskOpacity = target
                timer.invalidate()
                self.maskAnimationTimer = nil
            }
        }
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

    private func drawMagnifier() {
        guard let backgroundImage,
              let magnifierFrame,
              let magnifierSourceRect,
              let magnifierCursor,
              magnifierFrame.width > 1,
              magnifierFrame.height > 1,
              magnifierSourceRect.width > 1,
              magnifierSourceRect.height > 1
        else { return }

        let frame = magnifierFrame.intersection(bounds)
        guard !frame.isNull, !frame.isEmpty else { return }

        let clip = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        backgroundImage.draw(
            in: frame,
            from: magnifierSourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: isFlipped,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()

        let shadow = NSBezierPath(roundedRect: frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 10.5, yRadius: 10.5)
        shadow.lineWidth = 5
        NSColor.black.withAlphaComponent(0.75).setStroke()
        shadow.stroke()

        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11)
        border.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        border.stroke()

        let cursor = MagnifierLayout.cursorPosition(
            cursor: magnifierCursor,
            sourceRect: magnifierSourceRect,
            destinationFrame: frame
        )
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: cursor.x - 12, y: cursor.y))
        crosshair.line(to: CGPoint(x: cursor.x + 12, y: cursor.y))
        crosshair.move(to: CGPoint(x: cursor.x, y: cursor.y - 12))
        crosshair.line(to: CGPoint(x: cursor.x, y: cursor.y + 12))
        crosshair.lineCapStyle = .round
        // A dark under-stroke keeps the white cursor marker visible over
        // white or light captured content while preserving a white center on
        // dark content.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).addClip()
        crosshair.lineWidth = 4
        NSColor.black.withAlphaComponent(0.85).setStroke()
        crosshair.stroke()
        crosshair.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        crosshair.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
