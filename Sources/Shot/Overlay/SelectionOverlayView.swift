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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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

        // Follow the native Screenshot marquee: a neutral dashed outline does
        // the contrast work while tiny accent handles identify the active
        // selection without becoming a heavy blue rectangle.
        let frameRect = hole.insetBy(dx: -1, dy: -1)
        let marquee = NSBezierPath(
            roundedRect: frameRect,
            xRadius: radius + 1,
            yRadius: radius + 1
        )
        marquee.setLineDash(
            [OverlayFocusStyle.selectionDashLength, OverlayFocusStyle.selectionDashGap],
            count: 2,
            phase: 0
        )
        marquee.lineCapStyle = .butt
        marquee.lineJoinStyle = .miter
        marquee.lineWidth = OverlayFocusStyle.selectionContrastLineWidth
        NSColor.black.withAlphaComponent(OverlayFocusStyle.selectionContrastOpacity).setStroke()
        marquee.stroke()

        marquee.lineWidth = OverlayFocusStyle.selectionBorderLineWidth
        NSColor.white.withAlphaComponent(0.92).setStroke()
        marquee.stroke()

        drawSelectionHandles(in: frameRect, accent: accent)
    }

    private func drawSelectionHandles(in frameRect: CGRect, accent: NSColor) {
        guard min(frameRect.width, frameRect.height) >= OverlayFocusStyle.selectionHandleMinimumDimension else {
            return
        }

        let radius = OverlayFocusStyle.selectionHandleDiameter / 2
        let points = [
            CGPoint(x: frameRect.minX, y: frameRect.minY),
            CGPoint(x: frameRect.minX, y: frameRect.maxY),
            CGPoint(x: frameRect.maxX, y: frameRect.minY),
            CGPoint(x: frameRect.maxX, y: frameRect.maxY)
        ]

        for point in points {
            let handleFrame = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let handle = NSBezierPath(ovalIn: handleFrame)
            NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill()
            handle.fill()
            handle.lineWidth = OverlayFocusStyle.selectionBorderLineWidth
            accent.withAlphaComponent(OverlayFocusStyle.selectionBorderOpacity).setStroke()
            handle.stroke()
        }
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

        // A neutral contrast keyline keeps the target readable over both bright
        // and dark window contents. This is intentionally a crisp ring instead
        // of a large glow, matching native macOS focus treatment.
        let frameRect = hole.insetBy(dx: -0.5, dy: -0.5)
        let contrast = NSBezierPath(roundedRect: frameRect, xRadius: radius, yRadius: radius)
        contrast.lineWidth = OverlayFocusStyle.windowContrastLineWidth
        NSColor.black.withAlphaComponent(OverlayFocusStyle.windowContrastOpacity).setStroke()
        contrast.stroke()

        let border = NSBezierPath(roundedRect: frameRect, xRadius: radius, yRadius: radius)
        border.lineWidth = OverlayFocusStyle.windowBorderLineWidth
        NSColor.white.withAlphaComponent(OverlayFocusStyle.windowBorderOpacity).setStroke()
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

        let outerFrame = magnifierFrame.intersection(bounds)
        guard !outerFrame.isNull,
              !outerFrame.isEmpty,
              abs(outerFrame.width - magnifierFrame.width) < 0.01,
              abs(outerFrame.height - magnifierFrame.height) < 0.01
        else { return }

        let contentFrame = MagnifierLayout.contentFrame(
            for: outerFrame,
            chromeInset: OverlayFocusStyle.magnifierBezelInset
        )
        guard !contentFrame.isNull, !contentFrame.isEmpty else { return }

        // Keep the outer HUD plate, image window, and keylines on distinct
        // geometry. This prevents the bezel from stealing pixels from the
        // sampled image and keeps the border aligned at display edges.
        let bezel = NSBezierPath(ovalIn: outerFrame.insetBy(dx: 0.5, dy: 0.5))
        let shadow = NSShadow()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(OverlayFocusStyle.magnifierShadowOpacity)
        }
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        drawMagnifierBezelFill()
        bezel.fill()
        NSGraphicsContext.restoreGraphicsState()

        let clip = NSBezierPath(ovalIn: contentFrame)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        backgroundImage.draw(
            in: contentFrame,
            from: magnifierSourceRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: isFlipped,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()

        // Contrast keylines make the lens readable over either a bright or a
        // dark desktop. The inner keyline is the exact boundary of the pixels.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let outerBorder = NSBezierPath(ovalIn: outerFrame.insetBy(dx: 0.5, dy: 0.5))
            outerBorder.lineWidth = OverlayFocusStyle.magnifierBorderLineWidth
            NSColor.separatorColor
                .withAlphaComponent(OverlayFocusStyle.magnifierOuterBorderOpacity)
                .setStroke()
            outerBorder.stroke()

            let innerContrast = NSBezierPath(ovalIn: contentFrame.insetBy(dx: -0.5, dy: -0.5))
            innerContrast.lineWidth = OverlayFocusStyle.magnifierContrastLineWidth
            NSColor.shadowColor.withAlphaComponent(0.62).setStroke()
            innerContrast.stroke()

            let innerBorder = NSBezierPath(ovalIn: contentFrame.insetBy(dx: 0.5, dy: 0.5))
            innerBorder.lineWidth = OverlayFocusStyle.magnifierBorderLineWidth
            NSColor.labelColor
                .withAlphaComponent(OverlayFocusStyle.magnifierInnerBorderOpacity)
                .setStroke()
            innerBorder.stroke()
        }

        let cursor = MagnifierLayout.cursorPosition(
            cursor: magnifierCursor,
            sourceRect: magnifierSourceRect,
            destinationFrame: contentFrame
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
        NSBezierPath(ovalIn: contentFrame).addClip()
        crosshair.lineWidth = 4
        NSColor.black.withAlphaComponent(0.85).setStroke()
        crosshair.stroke()
        crosshair.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        crosshair.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMagnifierBezelFill() {
        let opacity = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? 0.96
            : OverlayFocusStyle.magnifierBezelOpacity
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.controlBackgroundColor
                .withAlphaComponent(opacity)
                .setFill()
        }
    }
}
