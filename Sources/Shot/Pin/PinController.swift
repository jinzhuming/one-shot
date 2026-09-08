import AppKit
import ShotKit

@MainActor
final class PinController: NSObject, NSWindowDelegate {
    static let shared = PinController()

    private var windows: [UUID: PinWindow] = [:]
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    private let addToHistory: (NSImage) -> Void

    init(addToHistory: ((NSImage) -> Void)? = nil) {
        self.addToHistory = addToHistory ?? { ScreenshotHistoryStore.add($0) }
        super.init()
    }

    var activeWindowCount: Int { windows.count }

    func present(
        _ image: NSImage,
        on screen: NSScreen?,
        onRestoreAnnotation: (() -> Void)? = nil
    ) {
        let id = UUID()
        let restoreAction: (() -> Void)?
        if let onRestoreAnnotation {
            restoreAction = { [weak self] in
                guard let self else { return }
                self.close(id)
                onRestoreAnnotation()
            }
        } else {
            restoreAction = nil
        }
        let view = PinContentView(
            image: image,
            onCopy: {
                if ImageExporter.copyToClipboard(image) {
                    SaveLocationPresenter.showCopied()
                }
            },
            onSave: { [weak self] in
                self?.save(image, id: id)
            },
            onRestore: restoreAction,
            onZoom: { [weak self] in
                self?.toggleZoom(id) ?? false
            },
            onClose: { [weak self] in
                self?.close(id)
            }
        )
        let visibleFrame = screen?.visibleFrame ?? .zero
        let size = PinLayout.windowSize(for: image.size, visibleFrame: visibleFrame)
        let window = PinWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.pinID = id
        window.imageSize = image.size
        window.compactSize = size
        window.onRequestClose = { [weak self] in self?.close(id) }
        window.onRequestCopy = { [weak view] in view?.copyImage() }
        window.onRequestSave = { [weak view] in view?.saveImage() }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = CaptureWindowLevels.pin
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.title = String(localized: "钉图")
        window.contentView = view
        if let screen {
            let origin = PinLayout.origin(size: size, visibleFrame: screen.visibleFrame, index: windows.count)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        addToHistory(image)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? PinWindow, let id = window.pinID else { return }
        saveTasks.removeValue(forKey: id)?.cancel()
        windows.removeValue(forKey: id)
        window.contentView = nil
    }

    func close(_ id: UUID) {
        saveTasks.removeValue(forKey: id)?.cancel()
        guard let window = windows.removeValue(forKey: id) else { return }
        window.contentView = nil
        window.onRequestCopy = nil
        window.onRequestSave = nil
        window.onRequestClose = nil
        window.close()
    }

    func closeAll() { for id in Array(windows.keys) { close(id) } }

    func relayoutForCurrentScreens() {
        for window in windows.values {
            guard let screen = CoordinateSpace.screen(for: window.frame)
                ?? CoordinateSpace.screen(containing: NSEvent.mouseLocation) ?? NSScreen.screens.first else { continue }
            let size = PinLayout.windowSize(for: window.imageSize, visibleFrame: screen.visibleFrame)
            let clamped = CGSize(width: min(window.frame.width, size.width), height: min(window.frame.height, size.height))
            let origin = EditorLayout.clampedOrigin(windowSize: clamped, preferred: window.frame.origin, visibleFrame: screen.visibleFrame, margin: 8)
            window.setFrame(CGRect(origin: origin, size: clamped), display: true)
        }
    }

    private func save(_ image: NSImage, id: UUID) {
        guard saveTasks[id] == nil, let window = windows[id] else { return }
        let settings = AppSettings.shared
        let format = settings.saveFormat
        guard let destination = ImageExporter.destination(settings: settings) else { return }
        (window.contentView as? PinContentView)?.setExporting(true)
        saveTasks[id] = Task { @MainActor [weak self, weak window] in
            defer {
                self?.saveTasks[id] = nil
                (window?.contentView as? PinContentView)?.setExporting(false)
            }
            do {
                let url = try await ImageExporter.save(image, format: format, destination: destination)
                guard !Task.isCancelled, self?.windows[id] != nil else { return }
                SaveLocationPresenter.showSaved(at: url, on: window?.screen)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.windows[id] != nil else { return }
                NSAlert(error: error).runModal()
            }
        }
    }

    private func toggleZoom(_ id: UUID) -> Bool {
        guard let window = windows[id] else { return false }
        let screen = window.screen ?? NSScreen.screens.max { lhs, rhs in
            let lhsIntersection = window.frame.intersection(lhs.frame)
            let rhsIntersection = window.frame.intersection(rhs.frame)
            return lhsIntersection.width * lhsIntersection.height
                > rhsIntersection.width * rhsIntersection.height
        }
        let visibleFrame = screen?.visibleFrame ?? window.frame
        let targetSize: CGSize
        if window.isPinZoomed {
            targetSize = window.compactSize
        } else {
            targetSize = PinLayout.zoomedWindowSize(
                for: window.imageSize,
                visibleFrame: visibleFrame
            )
        }
        let origin = PinLayout.origin(
            size: targetSize,
            visibleFrame: visibleFrame,
            around: CGPoint(x: window.frame.midX, y: window.frame.midY)
        )
        window.isPinZoomed.toggle()
        window.setFrame(
            CGRect(origin: origin, size: targetSize),
            display: true,
            animate: true
        )
        return window.isPinZoomed
    }
}

enum PinLayout {
    static let cornerRadius: CGFloat = 10
    static let toolbarInset: CGFloat = 8
    static let minimumWindowWidth: CGFloat = 176
    static let maximumImageWidth: CGFloat = 320
    static let maximumImageHeight: CGFloat = 260

    static func windowSize(for imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let sourceWidth = max(imageSize.width, 1)
        let sourceHeight = max(imageSize.height, 1)
        let availableWidth = visibleFrame.width > 0
            ? max(1, visibleFrame.width - 24)
            : sourceWidth
        let availableHeight = visibleFrame.height > 0
            ? max(1, visibleFrame.height - 24)
            : sourceHeight
        let maximumImageWidth = min(availableWidth, max(220, min(Self.maximumImageWidth, availableWidth * 0.35)))
        let maximumImageHeight = min(availableHeight, Self.maximumImageHeight)
        let scale = min(
            maximumImageWidth / sourceWidth,
            maximumImageHeight / sourceHeight,
            1
        )
        return CGSize(
            width: max(minimumWindowWidth, sourceWidth * scale),
            height: max(1, sourceHeight * scale)
        )
    }

    static func origin(size: CGSize, visibleFrame: CGRect, index: Int) -> CGPoint {
        let offset = CGFloat(index * 24)
        return RectMath.clampedOrigin(
            CGPoint(
                x: visibleFrame.maxX - size.width - 24 - offset,
                y: visibleFrame.maxY - size.height - 48 - offset
            ),
            size: size,
            in: visibleFrame.insetBy(dx: 12, dy: 12)
        )
    }

    static func zoomedWindowSize(for imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let sourceWidth = max(imageSize.width, 1)
        let sourceHeight = max(imageSize.height, 1)
        let availableWidth = visibleFrame.width > 0
            ? max(1, visibleFrame.width - 48)
            : sourceWidth
        let availableHeight = visibleFrame.height > 0
            ? max(1, visibleFrame.height - 48)
            : sourceHeight
        let scale = min(availableWidth / sourceWidth, availableHeight / sourceHeight)
        return CGSize(
            width: max(1, sourceWidth * scale),
            height: max(1, sourceHeight * scale)
        )
    }

    static func origin(size: CGSize, visibleFrame: CGRect, around center: CGPoint) -> CGPoint {
        RectMath.clampedOrigin(
            CGPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            ),
            size: size,
            in: visibleFrame.insetBy(dx: 12, dy: 12)
        )
    }
}

final class PinWindow: NSPanel {
    var pinID: UUID?
    var imageSize: CGSize = .zero
    var compactSize: CGSize = .zero
    var isPinZoomed = false
    var onRequestClose: (() -> Void)?
    var onRequestCopy: (() -> Void)?
    var onRequestSave: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function, .help])
        guard modifiers == .command, let character = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        switch character {
        case "c":
            onRequestCopy?()
            return true
        case "s":
            onRequestSave?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class PinContentView: NSView {
    private let imageView = NSImageView()
    private let actionBar: PinActionBarView
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onRestore: (() -> Void)?
    private let onZoom: () -> Bool
    private let onClose: () -> Void
    private var isExporting = false

    init(
        image: NSImage,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onRestore: (() -> Void)?,
        onZoom: @escaping () -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onSave = onSave
        self.onRestore = onRestore
        self.onZoom = onZoom
        self.onClose = onClose
        self.actionBar = PinActionBarView(
            onCopy: onCopy,
            onSave: onSave,
            onRestore: onRestore,
            onZoom: onZoom,
            onClose: onClose
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = PinLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(imageView)

        actionBar.alphaValue = 0
        addSubview(actionBar)

        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "钉图"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        let size = actionBar.intrinsicContentSize
        actionBar.frame = CGRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: PinLayout.toolbarInset,
            width: size.width,
            height: size.height
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if actionBar.alphaValue < 0.5, actionBar.frame.contains(point) {
            return imageView
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    func setExporting(_ exporting: Bool) {
        isExporting = exporting
        actionBar.setExporting(exporting)
        if exporting { setActionsVisible(true) }
    }

    override func mouseEntered(with event: NSEvent) {
        setActionsVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setActionsVisible(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if NSWorkspace.shared.isVoiceOverEnabled {
            setActionsVisible(true, animated: false)
        }
    }

    func copyImage() { onCopy() }
    func saveImage() { onSave() }
    func restoreAnnotation() { onRestore?() }
    func toggleZoom() { actionBar.setZoomed(onZoom()) }

    private func setActionsVisible(_ visible: Bool, animated: Bool = true) {
        let revealed = visible || isExporting || NSWorkspace.shared.isVoiceOverEnabled
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = InterfacePreferences.shared.reduceMotion ? 0 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                actionBar.animator().alphaValue = revealed ? 1 : 0
            }
        } else {
            actionBar.alphaValue = revealed ? 1 : 0
        }
    }
}

private final class PinActionBarView: NSView {
    private let effectView = HUDMaterialView()
    private let liftView = NSView()
    private let stackView = NSStackView()
    private let copyButton = PinIconButton()
    private let saveButton = PinIconButton()
    private let restoreButton = PinIconButton()
    private let zoomButton = PinIconButton()
    private let closeButton = PinIconButton()
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onRestore: (() -> Void)?
    private let onZoom: () -> Bool
    private let onClose: () -> Void

    init(
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onRestore: (() -> Void)?,
        onZoom: @escaping () -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onSave = onSave
        self.onRestore = onRestore
        self.onZoom = onZoom
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
        appearance = NSAppearance(named: .vibrantDark)

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        addSubview(effectView)

        liftView.wantsLayer = true
        liftView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(liftView)

        if HUDChrome.reduceTransparency {
            effectView.isHidden = true
            liftView.isHidden = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }

        configure(
            copyButton,
            title: String(localized: "复制"),
            systemImage: "doc.on.clipboard",
            help: String(localized: "将图片复制到剪贴板（⌘C）"),
            action: #selector(copyImage)
        )
        configure(
            saveButton,
            title: String(localized: "保存"),
            systemImage: "square.and.arrow.down",
            help: String(localized: "将图片保存到文件（⌘S）"),
            action: #selector(saveImage)
        )
        if onRestore != nil {
            configure(
                restoreButton,
                title: String(localized: "恢复标注"),
                systemImage: "pencil",
                help: String(localized: "恢复到非钉图的标注编辑状态"),
                action: #selector(restoreAnnotation)
            )
        }
        configure(
            zoomButton,
            title: String(localized: "放大查看"),
            systemImage: "arrow.up.left.and.arrow.down.right",
            help: String(localized: "放大钉图以便查看"),
            action: #selector(toggleZoom)
        )
        configure(
            closeButton,
            title: String(localized: "关闭"),
            systemImage: "xmark",
            help: String(localized: "关闭钉图（Esc）"),
            action: #selector(closePin)
        )

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        divider.setContentHuggingPriority(.required, for: .horizontal)
        divider.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        if onRestore != nil {
            stackView.addArrangedSubview(restoreButton)
        }
        stackView.addArrangedSubview(zoomButton)
        stackView.addArrangedSubview(divider)
        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(saveButton)
        let exportDivider = NSView()
        exportDivider.wantsLayer = true
        exportDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        exportDivider.setContentHuggingPriority(.required, for: .horizontal)
        exportDivider.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(exportDivider)
        NSLayoutConstraint.activate([
            exportDivider.widthAnchor.constraint(equalToConstant: 1),
            exportDivider.heightAnchor.constraint(equalToConstant: 18)
        ])
        stackView.addArrangedSubview(closeButton)
        stackView.setCustomSpacing(6, after: divider)
        stackView.setCustomSpacing(6, after: saveButton)
        stackView.setCustomSpacing(6, after: exportDivider)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 18)
        ])

        setAccessibilityElement(false)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "钉图操作"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var intrinsicContentSize: NSSize {
        let buttonCount = onRestore == nil ? 4 : 5
        let dividerCount = 2
        let itemCount = buttonCount + dividerCount
        let customSpacingCount = 3
        let regularSpacingCount = max(0, itemCount - 1 - customSpacingCount)
        let spacing = CGFloat(customSpacingCount * 6 + regularSpacingCount * 2)
        return CGSize(
            width: CGFloat(buttonCount) * AnnotationChromeMetrics.controlSize
                + CGFloat(dividerCount)
                + spacing
                + 10,
            height: 38
        )
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        liftView.frame = bounds
        stackView.frame = bounds
    }

    private func configure(
        _ button: PinIconButton,
        title: String,
        systemImage: String,
        help: String,
        action: Selector
    ) {
        let symbol = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
            .withSymbolConfiguration(symbol)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.toolTip = help
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(help)
        button.setAccessibilityRole(.button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: AnnotationChromeMetrics.controlSize),
            button.heightAnchor.constraint(equalToConstant: AnnotationChromeMetrics.controlSize)
        ])
    }

    func setExporting(_ exporting: Bool) {
        saveButton.isEnabled = !exporting
        saveButton.setAccessibilityValue(exporting ? String(localized: "正在保存") : String(localized: "保存"))
        saveButton.image = NSImage(systemSymbolName: exporting ? "hourglass" : "square.and.arrow.down", accessibilityDescription: nil)
    }

    @objc private func copyImage() { onCopy() }
    @objc private func saveImage() { onSave() }
    @objc private func restoreAnnotation() { onRestore?() }
    @objc private func toggleZoom() { setZoomed(onZoom()) }
    @objc private func closePin() { onClose() }

    func setZoomed(_ zoomed: Bool) {
        let title = zoomed ? String(localized: "恢复原大小") : String(localized: "放大查看")
        let help = zoomed
            ? String(localized: "恢复钉图原来的大小")
            : String(localized: "放大钉图以便查看")
        let systemImage = zoomed
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
        zoomButton.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: title
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        zoomButton.toolTip = help
        zoomButton.setAccessibilityLabel(title)
        zoomButton.setAccessibilityHelp(help)
    }
}

private final class PinIconButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if isHighlighted {
            fill = NSColor.white.withAlphaComponent(0.22)
        } else if isHovered {
            fill = NSColor.white.withAlphaComponent(0.14)
        } else {
            fill = .clear
        }
        if fill.alphaComponent > 0 {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
