import AppKit

@MainActor
enum SaveLocationPresenter {
    private static var panel: SaveConfirmationPanel?
    private static var dismissTask: Task<Void, Never>?

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

    static func showCopied(on screen: NSScreen? = nil) {
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        panel.configureCopied()
        if let screen = screen ?? screenUnderPointer() {
            panel.position(on: screen)
        }
        panel.orderFrontRegardless()
        panel.announce(String(localized: "截图已复制到剪贴板"))

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
    }

    func configureCopied() {
        fileURL = nil
        confirmationView.configureCopied()
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

    private let effectView = NSVisualEffectView()
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

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        if HUDChrome.reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }
        addSubview(effectView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.setAccessibilityLabel(String(localized: "截图已保存"))
        addSubview(titleLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        fileLabel.font = .systemFont(ofSize: 11)
        fileLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(fileLabel)

        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.target = self
        openButton.action = #selector(openFolder)
        openButton.setAccessibilityLabel(String(localized: "打开文件夹"))
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
        fileLabel.stringValue = fileURL.lastPathComponent
        fileLabel.isHidden = false
        openButton.isHidden = false
        toolTip = fileURL.path
        needsLayout = true
    }

    func configureCopied() {
        titleLabel.stringValue = String(localized: "截图已复制到剪贴板")
        titleLabel.setAccessibilityLabel(String(localized: "截图已复制到剪贴板"))
        setAccessibilityLabel(String(localized: "截图已复制到剪贴板"))
        fileLabel.stringValue = ""
        fileLabel.isHidden = true
        openButton.isHidden = true
        toolTip = nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds

        let buttonSize = openButton.fittingSize
        openButton.frame = CGRect(
            x: bounds.width - buttonSize.width - 12,
            y: (bounds.height - buttonSize.height) / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )
        let labelWidth = max(1, openButton.isHidden ? bounds.width - 28 : openButton.frame.minX - 30)
        titleLabel.frame = CGRect(x: 14, y: 38, width: labelWidth, height: 18)
        fileLabel.frame = CGRect(x: 14, y: 17, width: labelWidth, height: 16)
    }

    @objc private func openFolder() {
        onOpenFolder?()
    }
}
