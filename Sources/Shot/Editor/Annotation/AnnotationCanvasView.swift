import AppKit
import ShotKit

@MainActor
protocol AnnotationCanvasDelegate: AnyObject {
    func canvasDidReceive(_ event: CanvasEvent)
    func canvasDidBeginText(at imagePoint: CGPoint)
    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint)
    func canvasDidCancelText()
}

final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    weak var delegate: AnnotationCanvasDelegate?
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var annotations: [AnnotationElement] = [] {
        didSet { needsDisplay = true }
    }
    var sourceImageSize: CGSize = .zero
    var selectedTool: AnnotationToolID = .pen {
        didSet { refreshCursor() }
    }
    var strokeColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4

    private var editorChrome: TextEditorChrome?
    private var textView: AnnotationTextView?
    private var placeholder: NSTextField?
    private var textImageOrigin: CGPoint?
    private var pendingTextPoint: CGPoint?
    private var ignoreNextMouseUp = false
    private var isTrackingGesture = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role { .image }
    override func accessibilityLabel() -> String? { String(localized: "标注画布") }

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

        guard !annotations.isEmpty else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
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

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursorForCurrentTool)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let chrome = editorChrome {
            let chromePoint = convert(point, to: chrome)
            if let hit = chrome.hitTest(chromePoint) {
                return hit
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if isEditingText {
            commitTextIfNeeded()
            ignoreNextMouseUp = true
            return
        }
        if selectedTool == .text {
            pendingTextPoint = imageLocation(in: event)
            return
        }
        window?.makeFirstResponder(self)
        isTrackingGesture = true
        delegate?.canvasDidReceive(.down(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func mouseDragged(with event: NSEvent) {
        guard !ignoreNextMouseUp, selectedTool != .text else { return }
        delegate?.canvasDidReceive(.drag(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func mouseUp(with event: NSEvent) {
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
        isTrackingGesture = false
        delegate?.canvasDidReceive(.up(imageLocation(in: event), shift: shiftHeld(in: event)))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isTrackingGesture, selectedTool != .text else { return }
        delegate?.canvasDidReceive(.drag(imageLocationFromScreen(), shift: shiftHeld(in: event)))
    }

    func beginTextEditing(at imagePoint: CGPoint) {
        commitTextIfNeeded()
        let fontSize = AnnotationMath.fontSize(lineWidth: lineWidth)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let viewPoint = CanvasMapping.viewPoint(
            imagePoint: imagePoint,
            viewSize: bounds.size,
            imageSize: mappingImageSize
        )

        let chrome = TextEditorChrome()
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 6
        chrome.layer?.cornerCurve = .continuous
        chrome.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
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
        editor.textContainerInset = NSSize(width: 10, height: 8)
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

        layoutEditor(at: viewPoint)
        delegate?.canvasDidBeginText(at: imagePoint)
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.textView else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(editor)
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(editor)
            }
        }
    }

    func cancelTextEditing() {
        removeEditor()
    }

    var isEditingText: Bool { textView != nil }

    func commitTextIfNeeded() {
        guard let editor = textView, let origin = textImageOrigin else { return }
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        removeEditor()
        if !text.isEmpty {
            delegate?.canvasDidCommitText(text, at: origin)
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
    }

    private var cursorForCurrentTool: NSCursor {
        selectedTool == .text ? .iBeam : .crosshair
    }

    private func refreshCursor() {
        window?.invalidateCursorRects(for: self)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let editor = subviews.compactMap({ $0 as? NSTextView }).first {
            let editorPoint = convert(point, to: editor)
            return editor.hitTest(editorPoint) ?? editor
        }
        return self
    }
}

private final class AnnotationTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
