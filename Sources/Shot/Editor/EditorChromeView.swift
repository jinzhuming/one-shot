import AppKit
import Combine
import ShotKit
import SwiftUI

enum EditorPresentationStyle {
    case inPlace
    case windowed
}

final class EditorChromeView: NSView {
    private let canvasChrome = EditorCanvasChromeView()
    let canvas = AnnotationCanvasView()

    private let toolbarHost: NonDraggableHostingView<AnnotationToolbar>
    private let session: EditSession
    private let presentationStyle: EditorPresentationStyle
    private var arrangement: EditorArrangement
    private var windowedLayout: EditorWindowLayout?
    private let coordinator: CanvasCoordinator
    private var cancellable: AnyCancellable?

    init(
        session: EditSession,
        arrangement: EditorArrangement,
        presentationStyle: EditorPresentationStyle = .inPlace,
        windowedLayout: EditorWindowLayout? = nil,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.presentationStyle = presentationStyle
        self.arrangement = arrangement
        self.windowedLayout = windowedLayout
        self.coordinator = CanvasCoordinator(session: session)
        self.toolbarHost = NonDraggableHostingView(
            rootView: AnnotationToolbar(
                session: session,
                onCopy: onCopy,
                onSave: onSave,
                onClose: onClose,
                presentation: presentationStyle == .windowed ? .docked : .floating
            )
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = presentationStyle == .windowed
            ? NSColor.underPageBackgroundColor.cgColor
            : NSColor.clear.cgColor
        layer?.masksToBounds = false
        canvas.delegate = coordinator
        canvas.selectedTool = session.selectedTool
        canvas.wantsLayer = true
        canvasChrome.wantsLayer = true
        canvasChrome.layer?.borderWidth = 1
        canvasChrome.layer?.borderColor = NSColor.separatorColor.cgColor
        canvasChrome.layer?.shadowColor = NSColor.black.cgColor
        canvasChrome.layer?.shadowOpacity = 0.28
        canvasChrome.layer?.shadowRadius = 11
        canvasChrome.layer?.shadowOffset = CGSize(width: 0, height: -2)
        canvasChrome.setAccessibilityElement(false)
        toolbarHost.wantsLayer = true
        toolbarHost.layer?.isOpaque = false
        toolbarHost.layer?.backgroundColor = NSColor.clear.cgColor
        toolbarHost.layer?.masksToBounds = false
        toolbarHost.layer?.zPosition = 1
        toolbarHost.appearance = NSAppearance(named: .vibrantDark)
        toolbarHost.setAccessibilityElement(true)
        toolbarHost.setAccessibilityRole(.group)
        toolbarHost.setAccessibilityLabel(String(localized: "标注工具"))
        addSubview(canvasChrome)
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

    func apply(_ layout: EditorWindowLayout) {
        windowedLayout = layout
        setFrameSize(layout.contentSize)
        needsLayout = true
    }

    func commitPendingText() {
        canvas.commitTextIfNeeded()
    }

    override func layout() {
        super.layout()
        let layout: (canvas: CGRect, toolbar: CGRect)
        if presentationStyle == .windowed {
            let computed = EditorLayout.windowed(
                imageSize: session.document.baseImage.size,
                toolbarSize: toolbarFittingSize,
                contentSize: bounds.size
            )
            windowedLayout = computed
            layout = (computed.canvasFrame, computed.toolbarFrame)
        } else {
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
            layout = (arrangement.canvasFrame, toolbar)
        }
        canvas.frame = layout.canvas
        canvasChrome.frame = layout.canvas.insetBy(dx: -1, dy: -1)
        canvasChrome.layer?.shadowPath = CGPath(rect: canvasChrome.bounds, transform: nil)
        toolbarHost.frame = layout.toolbar
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
        canvas.selectedObjectID = session.document.selectedID
        canvas.sourceImageSize = session.document.baseImage.size
        canvas.selectedTool = session.selectedTool
        canvas.strokeColor = NSColor(session.color)
        canvas.lineWidth = session.lineWidth
        if canvas.isEditingText {
            if session.textEditOrigin == nil {
                canvas.cancelTextEditing()
            } else if session.selectedTool != .text && session.selectedTool != .select {
                canvas.commitTextIfNeeded()
            }
        }
    }
}

private final class EditorCanvasChromeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.separatorColor.cgColor
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

    func canvasDidBeginText(at imagePoint: CGPoint, replacing id: UUID?) {
        session.beginText(at: imagePoint, replacing: id)
    }

    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint, replacing id: UUID?) {
        session.commitText(string, at: imagePoint, replacing: id)
    }

    func canvasDidCancelText() {
        _ = session.cancelTextEditing()
    }
}

final class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
