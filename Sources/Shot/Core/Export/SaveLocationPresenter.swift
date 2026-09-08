import AppKit

@MainActor
enum SaveLocationPresenter {
    private static var panel: SaveConfirmationPanel?
    private static var dismissTask: Task<Void, Never>?

    static func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    static func showSaved(at url: URL, on screen: NSScreen? = nil) {
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        panel.configureSaved(fileURL: url)
        if let screen = screen ?? screenUnderPointer() {
            panel.position(on: screen)
        }
        panel.orderFrontRegardless()
        panel.announce(String(localized: "截图已保存"))

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self.panel === panel {
                self.panel = nil
            }
            self.dismissTask = nil
        }
    }

    static func showCopied(
        message: String = String(localized: "截图已复制到剪贴板"),
        on screen: NSScreen? = nil
    ) {
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        panel.configureCopied(message: message)
        if let screen = screen ?? screenUnderPointer() {
            panel.position(on: screen)
        }
        panel.orderFrontRegardless()
        panel.announce(message)

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self.panel === panel {
                self.panel = nil
            }
            self.dismissTask = nil
        }
    }

    private static func makePanel() -> SaveConfirmationPanel {
        let panel = SaveConfirmationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onOpenFolder = { [weak panel] in
            guard let url = panel?.fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            panel?.orderOut(nil)
        }
        self.panel = panel
        return panel
    }

    private static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.visibleFrame.contains(point) }
    }
}

@MainActor
private final class SaveConfirmationPanel: NSPanel {
    var fileURL: URL?
    var onOpenFolder: (() -> Void)?

    private let confirmationView = SaveConfirmationView()

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        isReleasedWhenClosed = false
        contentView = confirmationView
        confirmationView.onOpenFolder = { [weak self] in
            self?.onOpenFolder?()
        }
    }

    func configureSaved(fileURL: URL) {
        self.fileURL = fileURL
        confirmationView.configureSaved(fileURL: fileURL)
        setContentSize(confirmationView.preferredContentSize)
    }

    func configureCopied(message: String) {
        fileURL = nil
        confirmationView.configureCopied(message: message)
        setContentSize(confirmationView.preferredContentSize)
    }

    func announce(_ message: String) {
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = frame.size
        let origin = CGPoint(
            x: visible.maxX - size.width - 20,
            y: visible.minY + 20
        )
        setFrame(CGRect(origin: origin, size: size), display: false)
    }
}

@MainActor
private final class SaveConfirmationView: NSView {
    var onOpenFolder: (() -> Void)?

    private static let savedSize = NSSize(width: 404, height: 82)
    private static let copiedSize = NSSize(width: 276, height: 66)

    private let effectView = HUDMaterialView()
    private let statusImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: String(localized: "截图已保存"))
    private let fileLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton(
        title: String(localized: "打开文件夹"),
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.alphaValue = 0.92
        if HUDChrome.reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        addSubview(effectView)

        statusImageView.imageScaling = .scaleProportionallyUpOrDown
        statusImageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 24,
            weight: .medium
        )
        statusImageView.contentTintColor = NSColor.controlAccentColor
        statusImageView.setAccessibilityElement(false)
        addSubview(statusImageView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityLabel(String(localized: "截图已保存"))
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        fileLabel.font = .systemFont(ofSize: 11.5)
        fileLabel.textColor = NSColor.secondaryLabelColor
        fileLabel.maximumNumberOfLines = 1
        fileLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(fileLabel)

        openButton.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: String(localized: "打开文件夹")
        )
        openButton.imagePosition = .imageLeading
        openButton.imageScaling = .scaleProportionallyDown
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.target = self
        openButton.action = #selector(openFolder)
        openButton.setAccessibilityLabel(String(localized: "打开文件夹"))
        openButton.setAccessibilityHelp(String(localized: "在访达中显示截图文件"))
        addSubview(openButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureSaved(fileURL: URL) {
        titleLabel.stringValue = String(localized: "截图已保存")
        titleLabel.setAccessibilityLabel(String(localized: "截图已保存"))
        setAccessibilityLabel(String(localized: "截图已保存"))
        statusImageView.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: String(localized: "截图已保存")
        )
        fileLabel.stringValue = fileURL.lastPathComponent
        fileLabel.isHidden = false
        openButton.isHidden = false
        toolTip = fileURL.path
        needsLayout = true
    }

    func configureCopied(message: String) {
        titleLabel.stringValue = message
        titleLabel.setAccessibilityLabel(message)
        setAccessibilityLabel(message)
        statusImageView.image = NSImage(
            systemSymbolName: "doc.on.clipboard.fill",
            accessibilityDescription: message
        )
        fileLabel.stringValue = ""
        fileLabel.isHidden = true
        openButton.isHidden = true
        toolTip = nil
        needsLayout = true
    }

    var preferredContentSize: NSSize {
        openButton.isHidden ? Self.copiedSize : Self.savedSize
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds

        let iconSize = CGSize(width: 28, height: 28)
        statusImageView.frame = CGRect(
            x: 16,
            y: (bounds.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        let buttonSize = openButton.fittingSize
        openButton.frame = CGRect(
            x: bounds.width - buttonSize.width - 16,
            y: (bounds.height - buttonSize.height) / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )

        let textX = statusImageView.frame.maxX + 12
        let textMaxX = openButton.isHidden ? bounds.width - 16 : openButton.frame.minX - 16
        let labelWidth = max(1, textMaxX - textX)
        if fileLabel.isHidden {
            titleLabel.frame = CGRect(
                x: textX,
                y: (bounds.height - 20) / 2,
                width: labelWidth,
                height: 20
            )
        } else {
            titleLabel.frame = CGRect(x: textX, y: 43, width: labelWidth, height: 19)
            fileLabel.frame = CGRect(x: textX, y: 20, width: labelWidth, height: 16)
        }
    }

    @objc private func openFolder() {
        onOpenFolder?()
    }
}
