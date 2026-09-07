import AppKit
import Combine
import ShotKit
import SwiftUI

enum EditorPresentationStyle {
    case inPlace
    case windowed
}

final class EditorChromeView: NSView {
    private let canvasChrome: EditorCanvasChromeView
    let canvas = AnnotationCanvasView()

    private let toolbarHost: NonDraggableHostingView<AnnotationToolbar>
    private let session: EditSession
    private let presentationStyle: EditorPresentationStyle
    private let scrollableCanvas: Bool
    private let canvasScrollView: NSScrollView?
    private var didSetInitialScrollMagnification = false
    private var arrangement: EditorArrangement
    private var windowedLayout: EditorWindowLayout?
    private let coordinator: CanvasCoordinator
    private var cancellable: AnyCancellable?

    init(
        session: EditSession,
        arrangement: EditorArrangement,
        presentationStyle: EditorPresentationStyle = .inPlace,
        windowedLayout: EditorWindowLayout? = nil,
        scrollableCanvas: Bool = false,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.presentationStyle = presentationStyle
        self.scrollableCanvas = scrollableCanvas
        self.canvasScrollView = scrollableCanvas ? NSScrollView() : nil
        self.arrangement = arrangement
        self.windowedLayout = windowedLayout
        self.coordinator = CanvasCoordinator(session: session)
        self.canvasChrome = EditorCanvasChromeView(presentationStyle: presentationStyle)
        self.toolbarHost = NonDraggableHostingView(
            rootView: AnnotationToolbar(
                session: session,
                onCopy: onCopy,
                onSave: onSave,
                onClose: onClose,
                presentation: presentationStyle == .windowed ? .windowAdaptive : .floatingHUD
            )
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        updateBackgroundColor()
        canvas.delegate = coordinator
        canvas.selectedTool = session.selectedTool
        canvas.wantsLayer = true
        if let canvasScrollView {
            canvasScrollView.drawsBackground = true
            canvasScrollView.backgroundColor = NSColor.underPageBackgroundColor
            canvasScrollView.borderType = .noBorder
            canvasScrollView.hasVerticalScroller = true
            canvasScrollView.hasHorizontalScroller = true
            canvasScrollView.autohidesScrollers = true
            canvasScrollView.allowsMagnification = true
            canvasScrollView.minMagnification = 0.1
            canvasScrollView.maxMagnification = 4
            canvasScrollView.documentView = canvas
        }
        canvasChrome.setAccessibilityElement(false)
        toolbarHost.wantsLayer = true
        toolbarHost.layer?.isOpaque = false
        toolbarHost.layer?.backgroundColor = NSColor.clear.cgColor
        toolbarHost.layer?.masksToBounds = false
        toolbarHost.layer?.zPosition = 1
        if presentationStyle == .inPlace {
            toolbarHost.appearance = NSAppearance(named: .vibrantDark)
        }
        toolbarHost.setAccessibilityElement(true)
        toolbarHost.setAccessibilityRole(.group)
        toolbarHost.setAccessibilityLabel(String(localized: "标注工具"))
        addSubview(canvasChrome)
        if let canvasScrollView {
            addSubview(canvasScrollView)
        } else {
            addSubview(canvas)
        }
        addSubview(toolbarHost, positioned: .above, relativeTo: canvasScrollView ?? canvas)
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

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
        if presentationStyle == .windowed,
           scrollableCanvas,
           let canvasScrollView {
            let toolbarSize = toolbarFittingSize
            let toolbar = CGRect(
                x: 0,
                y: max(0, bounds.height - toolbarSize.height),
                width: bounds.width,
                height: min(toolbarSize.height, bounds.height)
            )
            let workspace = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(1, toolbar.minY)
            ).insetBy(
                dx: EditorLayout.windowedWorkspacePadding,
                dy: EditorLayout.windowedWorkspacePadding
            )
            toolbarHost.frame = toolbar
            canvasScrollView.frame = workspace
            canvasChrome.frame = workspace.insetBy(dx: -1, dy: -1)
            canvasChrome.layer?.shadowPath = CGPath(rect: canvasChrome.bounds, transform: nil)

            let imageSize = session.document.baseImage.size
            canvas.frame = CGRect(origin: .zero, size: imageSize)
            let availableWidth = max(1, canvasScrollView.contentView.bounds.width)
            let fitWidth = min(1, availableWidth / max(1, imageSize.width))
            if !didSetInitialScrollMagnification, availableWidth > 1 {
                canvasScrollView.magnification = max(canvasScrollView.minMagnification, fitWidth)
                didSetInitialScrollMagnification = true
            }
            return
        }

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
        guard presentationStyle == .inPlace else {
            super.mouseDown(with: event)
            return
        }
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
        canvas.calloutWrapText = session.calloutWrapText
        if canvas.isEditingText {
            if session.textEditOrigin == nil {
                canvas.cancelTextEditing()
            } else if session.selectedTool != .text && session.selectedTool != .callout && session.selectedTool != .select {
                canvas.commitTextIfNeeded()
            }
        }
    }

    private func updateBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = presentationStyle == .windowed
                ? NSColor.underPageBackgroundColor.cgColor
                : NSColor.clear.cgColor
        }
    }
}

private final class EditorCanvasChromeView: NSView {
    private let presentationStyle: EditorPresentationStyle

    init(presentationStyle: EditorPresentationStyle) {
        self.presentationStyle = presentationStyle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateChrome()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateChrome()
    }

    private func updateChrome() {
        let scale = max(window?.backingScaleFactor ?? 1, 1)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderWidth = presentationStyle == .windowed ? 1 / scale : 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.shadowColor = presentationStyle == .windowed
                ? NSColor.shadowColor.cgColor
                : NSColor.black.cgColor
            layer?.shadowOpacity = presentationStyle == .windowed ? 0.18 : 0.28
            layer?.shadowRadius = presentationStyle == .windowed ? 8 : 11
            layer?.shadowOffset = CGSize(width: 0, height: -2)
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

    func canvasDidBeginText(at imagePoint: CGPoint, replacing id: UUID?) {
        session.beginText(at: imagePoint, replacing: id)
    }

    func canvasDidCommitText(_ string: String, at imagePoint: CGPoint, replacing id: UUID?) {
        session.commitText(string, at: imagePoint, replacing: id)
    }

    func canvasDidBeginCallout(at rect: CGRect, replacing id: UUID?) {
        session.beginCallout(at: rect, replacing: id)
    }

    func canvasDidCommitCallout(_ string: String, in rect: CGRect, replacing id: UUID?) {
        session.commitCallout(string, in: rect, replacing: id)
    }

    func canvasDidCancelText() {
        _ = session.cancelTextEditing()
    }
}

final class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
