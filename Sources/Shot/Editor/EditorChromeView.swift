import AppKit
import Combine
import ShotKit
import SwiftUI

final class EditorChromeView: NSView {
    let canvas = AnnotationCanvasView()

    private let toolbarHost: NonDraggableHostingView<AnnotationToolbar>
    private let session: EditSession
    private var arrangement: EditorArrangement
    private let coordinator: CanvasCoordinator
    private var cancellable: AnyCancellable?

    init(
        session: EditSession,
        arrangement: EditorArrangement,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.arrangement = arrangement
        self.coordinator = CanvasCoordinator(session: session)
        self.toolbarHost = NonDraggableHostingView(
            rootView: AnnotationToolbar(session: session, onCopy: onCopy, onSave: onSave, onClose: onClose)
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        canvas.delegate = coordinator
        canvas.selectedTool = session.selectedTool
        canvas.wantsLayer = true
        toolbarHost.wantsLayer = true
        toolbarHost.layer?.isOpaque = false
        toolbarHost.layer?.backgroundColor = NSColor.clear.cgColor
        toolbarHost.layer?.masksToBounds = false
        toolbarHost.layer?.zPosition = 1
        toolbarHost.appearance = NSAppearance(named: .vibrantDark)
        toolbarHost.setAccessibilityElement(true)
        toolbarHost.setAccessibilityRole(.group)
        toolbarHost.setAccessibilityLabel(String(localized: "标注工具"))
        addSubview(canvas)
        addSubview(toolbarHost, positioned: .above, relativeTo: canvas)
        syncCanvas()
        cancellable = session.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.syncCanvas() }
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    var toolbarFittingSize: NSSize {
        let size = toolbarHost.fittingSize
        if size.width < 32 || size.height < 32 {
            return NSSize(
                width: EditorLayout.minContentWidth,
                height: EditorLayout.estimatedToolbarHeight
            )
        }
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    func apply(_ arrangement: EditorArrangement) {
        self.arrangement = arrangement
        setFrameSize(arrangement.windowFrame.size)
        needsLayout = true
    }

    func commitPendingText() {
        canvas.commitTextIfNeeded()
    }

    override func layout() {
        super.layout()
        canvas.frame = arrangement.canvasFrame
        var toolbar = arrangement.toolbarFrame
        let fitted = toolbarFittingSize
        if fitted.width > 32 {
            toolbar.size.width = min(fitted.width, max(1, bounds.width - 4))
            toolbar.origin.x = arrangement.toolbarFrame.midX - toolbar.width / 2
            toolbar.origin.x = RectMath.clamped(
                toolbar.origin.x,
                lower: 2,
                upper: bounds.width - toolbar.width - 2
            )
        }
        toolbarHost.frame = toolbar
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is already in this view's coordinate space. Convert it to each
        // child before asking that child to resolve the deepest hit view. Keeping
        // this boundary explicit is important because the editor root is
        // unflipped while both the canvas and SwiftUI hosting view are flipped.
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        if toolbarHost.frame.contains(point) {
            let toolbarPoint = convert(point, to: toolbarHost)
            return toolbarHost.hitTest(toolbarPoint) ?? toolbarHost
        }
        if canvas.frame.contains(point) {
            let canvasPoint = convert(point, to: canvas)
            return canvas.hitTest(canvasPoint) ?? canvas
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        dragWindow(from: event)
    }

    private func dragWindow(from start: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(
                CGPoint(
                    x: startOrigin.x + now.x - startMouse.x,
                    y: startOrigin.y + now.y - startMouse.y
                )
            )
        }
    }

    private func syncCanvas() {
        canvas.image = session.document.baseImage
        canvas.annotations = session.document.visibleElements
        canvas.sourceImageSize = session.document.baseImage.size
        canvas.selectedTool = session.selectedTool
        canvas.strokeColor = NSColor(session.color)
        canvas.lineWidth = session.lineWidth
        if canvas.isEditingText {
            if session.textEditOrigin == nil {
                canvas.cancelTextEditing()
            } else if session.selectedTool != .text {
                canvas.commitTextIfNeeded()
            }
        }
    }
}

final class CanvasCoordinator: NSObject, AnnotationCanvasDelegate {
    let session: EditSession

    init(session: EditSession) {
        self.session = session
    }

    func canvasDidReceive(_ event: CanvasEvent) {
        session.handle(event)
    }

    func canvasDidBeginText(at imagePoint: CGPoint) {
        session.beginText(at: imagePoint)
    }

    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint) {
        session.commitText(string, at: imagePoint)
    }

    func canvasDidCancelText() {
        _ = session.cancelTextEditing()
    }
}

final class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }
}
