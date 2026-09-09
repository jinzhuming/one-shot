import AppKit
import ShotKit

@MainActor
final class RecordingTargetOverlayController: NSObject {
    private enum TargetPresentation {
        case region(rect: CGRect, displayID: CGDirectDisplayID)
        case window(
            id: CGWindowID,
            rect: CGRect?,
            displayID: CGDirectDisplayID
        )
        case display(displayID: CGDirectDisplayID)

        var displayID: CGDirectDisplayID {
            switch self {
            case .region(_, let displayID), .window(_, _, let displayID), .display(let displayID):
                return displayID
            }
        }

        var rect: CGRect? {
            switch self {
            case .region(let rect, _):
                return rect
            case .window(_, let rect, _):
                return rect
            case .display:
                return nil
            }
        }

        var isWindow: Bool {
            if case .window = self { return true }
            return false
        }

        var isDisplay: Bool {
            if case .display = self { return true }
            return false
        }
    }

    private var windows: [CGDirectDisplayID: RecordingTargetOverlayWindow] = [:]
    private var target: TargetPresentation?
    private var catalog: WindowCatalog?
    private var controlBarFrame: CGRect?
    private var elapsedProvider: (() -> TimeInterval?)?
    private var timer: Timer?
    private var windowTrackingTask: Task<Void, Never>?
    private var state: RecordingState = .recording
    private var elapsed: TimeInterval?
    private var screenParametersObserver: NSObjectProtocol?

    override init() {
        super.init()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.relayout()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func present(
        target: RecordingTarget,
        on screen: NSScreen,
        catalog: WindowCatalog,
        elapsedProvider: @escaping () -> TimeInterval?
    ) {
        dismiss()
        self.catalog = catalog
        self.elapsedProvider = elapsedProvider
        self.elapsed = elapsedProvider()
        self.state = .recording
        self.controlBarFrame = RecordingControlBarController.frame(on: screen)
        self.target = makeTargetPresentation(target, on: screen, catalog: catalog)

        showOverlays()
        updateVisuals()

        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(updateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if case .window = self.target {
            windowTrackingTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, !Task.isCancelled else { return }
                    self.refreshWindowTarget()
                }
            }
        }
    }

    func update(state: RecordingState, elapsed: TimeInterval?) {
        self.state = state
        self.elapsed = elapsed
        updateVisuals()
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        windowTrackingTask?.cancel()
        windowTrackingTask = nil
        windows.values.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        target = nil
        catalog = nil
        controlBarFrame = nil
        elapsedProvider = nil
        elapsed = nil
    }

    @objc private func updateTimer() {
        elapsed = elapsedProvider?()
        updateVisuals()
    }

    private func makeTargetPresentation(
        _ target: RecordingTarget,
        on screen: NSScreen,
        catalog: WindowCatalog
    ) -> TargetPresentation {
        switch target {
        case .region(let selection):
            return .region(rect: selection.rect, displayID: selection.displayID)

        case .window(let id):
            let frame = initialWindowFrame(for: id, catalog: catalog)
            let displayID = frame.flatMap { CoordinateSpace.screen(for: $0)?.displayID }
                ?? screen.displayID
            return .window(id: id, rect: frame, displayID: displayID)

        case .display(let targetScreen):
            return .display(displayID: targetScreen.displayID)
        }
    }

    private func initialWindowFrame(for id: CGWindowID, catalog: WindowCatalog) -> CGRect? {
        if let window = catalog.windows.first(where: { $0.windowID == id }) {
            return window.frame
        }
        guard let window = catalog.scWindow(id: id),
              let geometry = CoordinateSpace.windowGeometry(fromCGWindowBounds: window.frame)
        else {
            return nil
        }
        return geometry.frame
    }

    private func refreshWindowTarget() {
        guard case .window(let id, let previousRect, let previousDisplayID) = target,
              let catalog else {
            return
        }

        catalog.refreshWindowsFromCG()
        guard let window = catalog.windows.first(where: { $0.windowID == id }) else {
            return
        }

        let currentRect = window.frame
        let currentDisplayID = CoordinateSpace.screen(for: currentRect)?.displayID
            ?? previousDisplayID
        guard currentRect != previousRect || currentDisplayID != previousDisplayID else {
            return
        }

        target = .window(id: id, rect: currentRect, displayID: currentDisplayID)
        updateVisuals()
    }

    private func showOverlays() {
        let liveIDs = Set(NSScreen.screens.map(\.displayID))
        for id in windows.keys where !liveIDs.contains(id) {
            if let window = windows.removeValue(forKey: id) {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
        }

        for screen in NSScreen.screens {
            let window = overlayWindow(for: screen)
            window.setFrame(screen.frame, display: false)
            if let view = window.contentView as? RecordingTargetOverlayView {
                view.setFrameSize(screen.frame.size)
            }
            window.orderFront(nil)
        }
    }

    private func relayout() {
        guard target != nil else { return }
        showOverlays()
        updateVisuals()
    }

    private func overlayWindow(for screen: NSScreen) -> RecordingTargetOverlayWindow {
        if let window = windows[screen.displayID] {
            return window
        }

        let window = RecordingTargetOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.isRestorable = false
        window.level = CaptureWindowLevels.overlay
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.animationBehavior = .none
        window.contentView = RecordingTargetOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        )
        windows[screen.displayID] = window
        return window
    }

    private func updateVisuals() {
        guard let target else { return }
        for screen in NSScreen.screens {
            guard let window = windows[screen.displayID],
                  let view = window.contentView as? RecordingTargetOverlayView else {
                continue
            }

            let isTargetDisplay = screen.displayID == target.displayID
            let globalTargetRect = target.rect?.intersection(screen.frame)
            let localTargetRect: CGRect?
            if let globalTargetRect,
               !globalTargetRect.isNull,
               !globalTargetRect.isEmpty {
                let inWindow = window.convertFromScreen(globalTargetRect)
                localTargetRect = view.convert(inWindow, from: nil)
            } else {
                localTargetRect = nil
            }

            view.update(
                targetRect: localTargetRect,
                isWindow: target.isWindow,
                isFullScreen: target.isDisplay && isTargetDisplay,
                state: state,
                elapsed: elapsed ?? 0,
                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            )

            let hud = view.statusHUD
            hud.isHidden = !isTargetDisplay
            guard isTargetDisplay else { continue }

            hud.update(state: state, elapsed: elapsed ?? 0)
            let badgeGlobalFrame = RecordingIndicatorLayout.badgeFrame(
                size: hud.intrinsicContentSize,
                targetRect: target.rect?.intersection(screen.frame),
                visibleFrame: screen.visibleFrame,
                reservedFrame: screen.displayID == controlBarDisplayID ? controlBarFrame : nil
            )
            let inWindow = window.convertFromScreen(badgeGlobalFrame)
            hud.frame = view.convert(inWindow, from: nil)
        }
    }

    private var controlBarDisplayID: CGDirectDisplayID? {
        controlBarFrame.flatMap { CoordinateSpace.screen(for: $0)?.displayID }
    }
}

final class RecordingTargetOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class RecordingTargetOverlayView: NSView {
    let statusHUD = RecordingStatusHUDView(frame: .zero)

    private var targetRect: CGRect?
    private var isWindowTarget = false
    private var isFullScreen = false
    private var state: RecordingState = .recording
    private var elapsed: TimeInterval = 0
    private var reduceTransparency = false

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(statusHUD)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        targetRect: CGRect?,
        isWindow: Bool,
        isFullScreen: Bool,
        state: RecordingState,
        elapsed: TimeInterval,
        reduceTransparency: Bool
    ) {
        self.targetRect = targetRect
        self.isWindowTarget = isWindow
        self.isFullScreen = isFullScreen
        self.state = state
        self.elapsed = elapsed
        self.reduceTransparency = reduceTransparency
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if isFullScreen {
            drawFullScreenBorder()
            return
        }

        guard let targetRect,
              !targetRect.isNull,
              !targetRect.isEmpty else {
            return
        }

        let target = targetRect.intersection(bounds)
        guard !target.isNull, !target.isEmpty else { return }

        let radius: CGFloat = isWindowTarget ? 6 : 2
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(roundedRect: target, xRadius: radius, yRadius: radius))
        mask.windingRule = .evenOdd
        let opacity = reduceTransparency
            ? RecordingIndicatorLayout.reducedTransparencyMaskOpacity
            : RecordingIndicatorLayout.defaultMaskOpacity
        NSColor.black.withAlphaComponent(opacity).setFill()
        mask.fill()

        drawTargetBorder(target, radius: radius)
    }

    private func drawTargetBorder(_ target: CGRect, radius: CGFloat) {
        let frameRect = target.insetBy(dx: -1, dy: -1)
        let contrast = NSBezierPath(roundedRect: frameRect, xRadius: radius + 1, yRadius: radius + 1)
        contrast.lineWidth = 5
        NSColor.black.withAlphaComponent(0.78).setStroke()
        contrast.stroke()

        let border = NSBezierPath(roundedRect: frameRect, xRadius: radius + 1, yRadius: radius + 1)
        border.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        border.stroke()

        let corners = FocusFrameGeometry.cornerSegments(in: frameRect)
        guard !corners.isEmpty else { return }
        let cornerPath = NSBezierPath()
        for segment in corners {
            cornerPath.move(to: segment.start)
            cornerPath.line(to: segment.end)
        }
        cornerPath.lineWidth = 2
        cornerPath.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        cornerPath.stroke()
    }

    private func drawFullScreenBorder() {
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.black.withAlphaComponent(0.78).setStroke()
        border.stroke()
        let accent = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        accent.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        accent.stroke()
    }
}

final class RecordingStatusHUDView: NSView {
    private let effectView = HUDMaterialView()
    private let dotView = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = stackView.fittingSize
        return NSSize(width: ceil(size.width) + 16, height: 26)
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        stackView.frame = bounds.insetBy(dx: 8, dy: 3)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(state: RecordingState, elapsed: TimeInterval) {
        statusLabel.stringValue = statusText(for: state)
        elapsedLabel.stringValue = RecordingLayout.formattedDuration(elapsed)
        dotView.layer?.backgroundColor = dotColor(for: state).cgColor
        setAccessibilityValue("\(statusLabel.stringValue) \(elapsedLabel.stringValue)")
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        addSubview(effectView)

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.setAccessibilityElement(false)

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.setAccessibilityElement(false)

        elapsedLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        elapsedLabel.textColor = .white.withAlphaComponent(0.88)
        elapsedLabel.alignment = .right
        elapsedLabel.setAccessibilityElement(false)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(dotView)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(elapsedLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            elapsedLabel.widthAnchor.constraint(equalToConstant: 42)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "录制目标"))
        update(state: .recording, elapsed: 0)
    }

    private func statusText(for state: RecordingState) -> String {
        switch state {
        case .recording:
            return String(localized: "正在录制")
        case .paused:
            return String(localized: "已暂停")
        case .starting, .resuming:
            return String(localized: "正在准备录屏…")
        case .pausing:
            return String(localized: "正在暂停…")
        case .stopping:
            return String(localized: "正在保存录屏…")
        default:
            return String(localized: "录屏")
        }
    }

    private func dotColor(for state: RecordingState) -> NSColor {
        switch state {
        case .recording:
            return .systemRed
        case .paused:
            return .systemOrange
        default:
            return .systemGray
        }
    }
}
