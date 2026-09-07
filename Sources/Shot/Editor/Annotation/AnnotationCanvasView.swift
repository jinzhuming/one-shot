import AppKit
import ShotKit

@MainActor
protocol AnnotationCanvasDelegate: AnyObject {
    func canvasDidReceive(_ event: CanvasEvent)
    func canvasDidBeginText(at imagePoint: CGPoint, replacing id: UUID?)
    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint, replacing id: UUID?)
    func canvasDidBeginCallout(at rect: CGRect, replacing id: UUID?)
    func canvasDidCommitCallout(_ string: String, in rect: CGRect, replacing id: UUID?)
    func canvasDidCancelText()
}

extension AnnotationCanvasDelegate {
    func canvasDidBeginCallout(at rect: CGRect, replacing id: UUID?) {}
    func canvasDidCommitCallout(_ string: String, in rect: CGRect, replacing id: UUID?) {}
}

final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    weak var delegate: AnnotationCanvasDelegate?
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var annotations: [AnnotationObject] = [] {
        didSet { needsDisplay = true }
    }
    var selectedObjectID: UUID? {
        didSet { needsDisplay = true }
    }
    var sourceImageSize: CGSize = .zero
    var selectedTool: AnnotationToolID = .pen {
        didSet { refreshCursor() }
    }
    var strokeColor: NSColor = .systemRed {
        didSet { updateTextEditorAppearance() }
    }
    var lineWidth: CGFloat = 4 {
        didSet { relayoutTextEditor() }
    }
    var calloutWrapText: Bool = true {
        didSet { relayoutTextEditor() }
    }
    private var calloutTextScale: CGFloat = 1 {
        didSet { relayoutTextEditor() }
    }

    private var editorChrome: TextEditorChrome?
    private var textView: AnnotationTextView?
    private var placeholder: NSTextField?
    private var textImageOrigin: CGPoint?
    private var textReplacingID: UUID?
    private var calloutEditingRect: CGRect?
    private var pendingTextPoint: CGPoint?
    private var pendingCalloutStart: CGPoint?
    private var ignoreNextMouseUp = false
    private var isTrackingGesture = false
    private var isSpaceHeld = false
    private var isPanningCanvas = false
    private var panStartWindowPoint: CGPoint?
    private var panStartBoundsOrigin: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role { .image }
    override func accessibilityLabel() -> String? { String(localized: "标注画布") }
    override func accessibilityValue() -> Any? {
        guard selectedTool == .select else { return String(localized: "绘制模式") }
        return selectedObjectID == nil
            ? String(localized: "未选择标注")
            : String(localized: "已选择标注，可移动或缩放")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        bounds.fill()
        guard let image else { return }

        image.draw(
            in: bounds,
            from: CGRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        let imageSize = image.size
        if imageSize.width > 0, imageSize.height > 0,
           let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(
                x: bounds.width / imageSize.width,
                y: bounds.height / imageSize.height
            )
            AnnotationRenderer.draw(
                annotations,
                baseImage: image,
                in: CGRect(origin: .zero, size: imageSize)
            )
            context.restoreGState()
        }
        drawSelectionOverlay()
    }

    override func layout() {
        super.layout()
        guard let textImageOrigin, editorChrome != nil else { return }
        let viewPoint = CanvasMapping.viewPoint(
            imagePoint: textImageOrigin,
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )
        layoutEditor(at: viewPoint)
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursorForCurrentTool)
    }

    override func mouseDown(with event: NSEvent) {
        if isEditingText {
            commitTextIfNeeded()
            ignoreNextMouseUp = true
            return
        }
        if isSpaceHeld {
            beginCanvasPan(with: event)
            return
        }
        if selectedTool == .text {
            pendingTextPoint = imageLocation(in: event)
            return
        }
        if selectedTool == .callout {
            pendingCalloutStart = imageLocation(in: event)
            window?.makeFirstResponder(self)
            isTrackingGesture = true
            delegate?.canvasDidReceive(.down(imageLocation(in: event), shift: shiftHeld(in: event)))
            return
        }
        if selectedTool == .select, event.clickCount == 2,
           let selectedObjectID,
           let selected = annotations.first(where: { $0.id == selectedObjectID }) {
            switch selected.element {
            case .text(let string, let origin, _):
                beginTextEditing(at: origin, initialText: string, replacingID: selected.id)
                return
            case .callout(let string, let rect, let style):
                beginTextEditing(
                    at: rect.origin,
                    initialText: string,
                    replacingID: selected.id,
                    calloutRect: rect,
                    calloutTextScale: style.textScale
                )
                return
            default:
                break
            }
        }
        window?.makeFirstResponder(self)
        isTrackingGesture = true
        delegate?.canvasDidReceive(.down(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanningCanvas {
            updateCanvasPan(with: event)
            return
        }
        guard !ignoreNextMouseUp, selectedTool != .text else { return }
        delegate?.canvasDidReceive(.drag(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func mouseUp(with event: NSEvent) {
        if isPanningCanvas {
            endCanvasPan()
            return
        }
        if ignoreNextMouseUp {
            ignoreNextMouseUp = false
            return
        }
        let point = pendingTextPoint ?? imageLocation(in: event)
        pendingTextPoint = nil
        if selectedTool == .text {
            beginTextEditing(at: point)
            return
        }
        if selectedTool == .callout {
            let start = pendingCalloutStart ?? point
            pendingCalloutStart = nil
            isTrackingGesture = false
            delegate?.canvasDidReceive(.up(point, shift: shiftHeld(in: event)))
            beginCalloutEditing(from: start, to: point, shift: shiftHeld(in: event))
            return
        }
        isTrackingGesture = false
        delegate?.canvasDidReceive(.up(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            setSpaceHeld(true)
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            setSpaceHeld(false)
            return
        }
        super.keyUp(with: event)
    }

    func setSpaceHeld(_ held: Bool) {
        isSpaceHeld = held
        if !held, !isPanningCanvas {
            cursorForCurrentTool.set()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isTrackingGesture, selectedTool != .text else { return }
        delegate?.canvasDidReceive(.drag(imageLocationFromScreen(), shift: shiftHeld(in: event)))
    }

    func beginTextEditing(
        at imagePoint: CGPoint,
        initialText: String = "",
        replacingID: UUID? = nil,
        calloutRect: CGRect? = nil,
        calloutTextScale: CGFloat = 1
    ) {
        commitTextIfNeeded()
        var editorStyle = AnnotationStyle()
        editorStyle.color = strokeColor
        editorStyle.lineWidth = lineWidth
        editorStyle.textScale = calloutRect == nil ? 1 : calloutTextScale
        let font = calloutRect == nil
            ? NSFont.systemFont(ofSize: AnnotationMath.fontSize(lineWidth: lineWidth), weight: .medium)
            : AnnotationCalloutLayout.font(for: editorStyle)
        let viewPoint = CanvasMapping.viewPoint(
            imagePoint: imagePoint,
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )

        let chrome = TextEditorChrome()
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 6
        chrome.layer?.cornerCurve = .continuous
        chrome.layer?.backgroundColor = calloutRect == nil
            ? NSColor.black.withAlphaComponent(0.55).cgColor
            : strokeColor.withAlphaComponent(0.14).cgColor
        chrome.layer?.borderWidth = 1
        chrome.layer?.borderColor = strokeColor.withAlphaComponent(0.85).cgColor

        let editor = AnnotationTextView()
        editor.delegate = self
        editor.font = font
        editor.textColor = strokeColor
        editor.insertionPointColor = strokeColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.usesFontPanel = false
        editor.usesFindPanel = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textContainerInset = calloutRect == nil
            ? NSSize(width: 10, height: 8)
            : .zero
        editor.textContainer?.lineFragmentPadding = calloutRect == nil ? 5 : 0
        editor.string = initialText
        editor.setAccessibilityLabel(String(localized: "文字"))

        let hint = NSTextField(labelWithString: String(localized: "输入文字"))
        hint.font = font
        hint.textColor = strokeColor.withAlphaComponent(0.45)
        hint.drawsBackground = false
        hint.isBezeled = false
        hint.isEditable = false
        hint.isSelectable = false
        hint.lineBreakMode = .byTruncatingTail

        chrome.addSubview(hint)
        chrome.addSubview(editor)
        addSubview(chrome)

        editorChrome = chrome
        textView = editor
        placeholder = hint
        textImageOrigin = imagePoint
        textReplacingID = replacingID
        calloutEditingRect = calloutRect?.standardized
        self.calloutTextScale = calloutRect == nil ? 1 : calloutTextScale

        layoutEditor(at: viewPoint)
        if let calloutRect {
            delegate?.canvasDidBeginCallout(at: calloutRect, replacing: replacingID)
        } else {
            delegate?.canvasDidBeginText(at: imagePoint, replacing: replacingID)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.textView else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(editor)
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(editor)
            }
        }
    }

    private func beginCalloutEditing(from start: CGPoint, to end: CGPoint, shift: Bool) {
        let imageBounds = CGRect(origin: .zero, size: mappingImageSize)
        var rect = SelectionGeometry.rect(from: start, to: end, square: shift)
        if !AnnotationMath.isSignificantRect(rect) {
            rect = CGRect(
                x: start.x,
                y: start.y,
                width: min(180, imageBounds.width),
                height: min(72, imageBounds.height)
            )
        }
        rect.size.width = min(rect.width, imageBounds.width)
        rect.size.height = min(rect.height, imageBounds.height)
        rect.origin.x = min(max(imageBounds.minX, rect.origin.x), imageBounds.maxX - rect.width)
        rect.origin.y = min(max(imageBounds.minY, rect.origin.y), imageBounds.maxY - rect.height)
        beginTextEditing(at: rect.origin, calloutRect: rect)
    }

    func cancelTextEditing() {
        removeEditor()
    }

    var isEditingText: Bool { textView != nil }

    func commitTextIfNeeded() {
        guard let editor = textView, let origin = textImageOrigin else { return }
        let replacingID = textReplacingID
        let calloutRect = calloutEditingRect
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        removeEditor()
        if !text.isEmpty {
            if let calloutRect {
                delegate?.canvasDidCommitCallout(text, in: calloutRect, replacing: replacingID)
            } else {
                delegate?.canvasDidCommitText(text, at: origin, replacing: replacingID)
            }
        } else {
            delegate?.canvasDidCancelText()
        }
    }

    func textDidChange(_ notification: Notification) {
        placeholder?.isHidden = !(textView?.string.isEmpty ?? true)
        if let chrome = editorChrome {
            layoutEditor(at: chrome.frame.origin)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            commitTextIfNeeded()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            commitTextIfNeeded()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            delegate?.canvasDidCancelText()
            return true
        }
        return false
    }

    private func layoutEditor(at origin: CGPoint) {
        guard let chrome = editorChrome, let editor = textView, let hint = placeholder else { return }
        if let calloutEditingRect {
            let layout = calloutLayout(for: editor.string, in: calloutEditingRect)
            let topLeft = CanvasMapping.viewPoint(
                imagePoint: CGPoint(x: layout.body.minX, y: layout.body.minY),
                viewSize: bounds.size,
                imageSize: mappingImageSize
            )
            let bottomRight = CanvasMapping.viewPoint(
                imagePoint: CGPoint(x: layout.body.maxX, y: layout.body.maxY),
                viewSize: bounds.size,
                imageSize: mappingImageSize
            )
            let inset: CGFloat = 4
            var frame = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            ).standardized
            frame.size.width = max(72, frame.width)
            frame.size.height = max(44, frame.height)
            frame.size.width = min(frame.width, max(72, bounds.width - inset * 2))
            frame.size.height = min(frame.height, max(44, bounds.height - inset * 2))
            frame.origin.x = min(max(inset, frame.origin.x), max(inset, bounds.maxX - inset - frame.width))
            frame.origin.y = min(max(inset, frame.origin.y), max(inset, bounds.maxY - inset - frame.height))
            chrome.frame = frame
            editor.frame = chrome.bounds.insetBy(dx: 10, dy: 8)
            hint.frame = editor.frame
            hint.isHidden = !editor.string.isEmpty
            return
        }
        let fontSize = editor.font?.pointSize ?? AnnotationMath.fontSize(lineWidth: lineWidth)
        let inset: CGFloat = 4
        let available = bounds.insetBy(dx: inset, dy: inset)
        let minWidth = min(max(120, fontSize * 8), max(32, available.width))
        let minHeight = min(max(44, fontSize * 1.7 + 20), max(24, available.height))
        let maxWidth = max(minWidth, available.width)
        let maxHeight = max(minHeight, available.height)

        editor.textContainer?.containerSize = NSSize(width: maxWidth - 4, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = false
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        let used = editor.layoutManager?.usedRect(for: editor.textContainer!) ?? .zero

        let width = min(max(minWidth, ceil(used.width) + 28), maxWidth)
        let height = min(max(minHeight, ceil(used.height) + 24), maxHeight)
        var x = origin.x
        var y = origin.y
        if x + width > bounds.maxX - inset { x = bounds.maxX - inset - width }
        if y + height > bounds.maxY - inset { y = bounds.maxY - inset - height }
        x = max(inset, x)
        y = max(inset, y)
        chrome.frame = CGRect(x: x, y: y, width: width, height: height)
        editor.frame = chrome.bounds
        hint.frame = chrome.bounds.insetBy(dx: 14, dy: 10)
        hint.isHidden = !editor.string.isEmpty
    }

    private func removeEditor() {
        if let window, let textView, window.firstResponder === textView {
            window.makeFirstResponder(self)
        }
        editorChrome?.removeFromSuperview()
        editorChrome = nil
        textView = nil
        placeholder = nil
        textImageOrigin = nil
        textReplacingID = nil
        calloutEditingRect = nil
        calloutTextScale = 1
    }

    private func calloutLayout(for text: String, in rect: CGRect) -> AnnotationCalloutLayout {
        var style = AnnotationStyle()
        style.color = strokeColor
        style.lineWidth = lineWidth
        style.textScale = calloutTextScale
        style.calloutWrapText = calloutWrapText
        return AnnotationCalloutLayout.layout(
            text: text,
            in: rect,
            style: style,
            wrapsText: calloutWrapText
        )
    }

    private func relayoutTextEditor() {
        guard let origin = textImageOrigin, editorChrome != nil else { return }
        let viewPoint = CanvasMapping.viewPoint(
            imagePoint: origin,
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )
        layoutEditor(at: viewPoint)
    }

    private func updateTextEditorAppearance() {
        guard let chrome = editorChrome else { return }
        chrome.layer?.backgroundColor = calloutEditingRect == nil
            ? NSColor.black.withAlphaComponent(0.55).cgColor
            : strokeColor.withAlphaComponent(0.14).cgColor
        chrome.layer?.borderColor = strokeColor.withAlphaComponent(0.85).cgColor
        textView?.textColor = strokeColor
        textView?.insertionPointColor = strokeColor
        placeholder?.textColor = strokeColor.withAlphaComponent(0.45)
    }

    private var cursorForCurrentTool: NSCursor {
        switch selectedTool {
        case .text: return .iBeam
        case .select: return .arrow
        default: return .crosshair
        }
    }

    private func drawSelectionOverlay() {
        guard selectedTool == .select,
              let selectedObjectID,
              let selected = annotations.first(where: { $0.id == selectedObjectID }) else { return }
        let imageBounds = selected.bounds
        let origin = CanvasMapping.viewPoint(
            imagePoint: CGPoint(x: imageBounds.minX, y: imageBounds.minY),
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )
        let maxPoint = CanvasMapping.viewPoint(
            imagePoint: CGPoint(x: imageBounds.maxX, y: imageBounds.maxY),
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )
        let selectionRect = CGRect(
            x: origin.x,
            y: origin.y,
            width: maxPoint.x - origin.x,
            height: maxPoint.y - origin.y
        ).standardized

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 1
        let dash: [CGFloat] = [4, 3]
        border.setLineDash(dash, count: dash.count, phase: 0)
        border.stroke()

        let handleSize: CGFloat = 8
        let centers = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY)
        ]
        for center in centers {
            let handle = CGRect(
                x: center.x - handleSize / 2,
                y: center.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSColor.controlAccentColor.setFill()
            handle.fill()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: handle)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    private func refreshCursor() {
        window?.invalidateCursorRects(for: self)
        cursorForCurrentTool.set()
    }

    private func beginCanvasPan(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        isPanningCanvas = true
        panStartWindowPoint = event.locationInWindow
        panStartBoundsOrigin = scrollView.contentView.bounds.origin
        window?.makeFirstResponder(self)
        NSCursor.closedHand.set()
    }

    private func updateCanvasPan(with event: NSEvent) {
        guard let scrollView = enclosingScrollView,
              let panStartWindowPoint,
              let panStartBoundsOrigin else { return }
        let magnification = max(scrollView.magnification, 0.001)
        let deltaX = (event.locationInWindow.x - panStartWindowPoint.x) / magnification
        let deltaY = (event.locationInWindow.y - panStartWindowPoint.y) / magnification
        var origin = panStartBoundsOrigin
        origin.x -= deltaX
        origin.y += deltaY
        scrollView.contentView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func endCanvasPan() {
        isPanningCanvas = false
        panStartWindowPoint = nil
        panStartBoundsOrigin = nil
        cursorForCurrentTool.set()
    }

    private func imageLocation(in event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return mappedImagePoint(viewPoint)
    }

    private func imageLocationFromScreen() -> CGPoint {
        guard let window else { return .zero }
        let windowPoint = window.convertFromScreen(
            NSRect(origin: NSEvent.mouseLocation, size: .zero)
        ).origin
        return mappedImagePoint(convert(windowPoint, from: nil))
    }

    private func mappedImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        CanvasMapping.imagePoint(
            viewPoint: viewPoint,
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )
    }

    private func shiftHeld(in event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift)
    }

    private var mappingImageSize: CGSize {
        if sourceImageSize.width > 0, sourceImageSize.height > 0 {
            return sourceImageSize
        }
        return image?.size ?? bounds.size
    }
}

private final class TextEditorChrome: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

private final class AnnotationTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
