import AppKit
import ShotKit

@MainActor
final class ScrollCaptureHUD {
    private var panel: NSPanel?
    private var contentView: ScrollCaptureHUDView?
    private var displayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.relayout() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show(on screen: NSScreen, onFinish: @escaping @MainActor () -> Void) {
        hide()
        displayID = screen.displayID

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 332, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = CaptureWindowLevels.modeBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let view = ScrollCaptureHUDView(
            frame: panel.contentRect(forFrameRect: panel.frame),
            onFinish: onFinish
        )
        panel.contentView = view
        self.panel = panel
        self.contentView = view
        relayout()
        panel.orderFrontRegardless()
    }

    private func relayout() {
        guard let panel, let contentView, let displayID else { return }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            hide()
            return
        }
        let size = contentView.preferredSize(maxWidth: max(1, screen.visibleFrame.width - 32))
        panel.setFrame(InterfaceLayout.bottomFrame(size: size, in: screen.visibleFrame), display: true)
    }

    func update(progress: ScrollCaptureProgress) {
        contentView?.update(progress: progress)
        relayout()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        contentView = nil
        displayID = nil
    }
}

@MainActor
private final class ScrollCaptureHUDView: NSView {
    private let effectView = HUDMaterialView()
    private let titleLabel = NSTextField(labelWithString: String(localized: "正在采集滚动截图…"))
    private let detailLabel = NSTextField(labelWithString: String(localized: "滚动内容，完成后按 Return"))
    private let finishButton = NSButton(title: String(localized: "完成"), target: nil, action: nil)
    private let onFinish: @MainActor () -> Void

    init(frame frameRect: NSRect, onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        addSubview(effectView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.setAccessibilityLabel(String(localized: "正在采集滚动截图"))
        addSubview(titleLabel)

        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setAccessibilityLabel(String(localized: "滚动内容，完成后按 Return"))
        addSubview(detailLabel)

        finishButton.bezelStyle = .rounded
        finishButton.controlSize = .small
        finishButton.target = self
        finishButton.action = #selector(finish)
        finishButton.setAccessibilityLabel(String(localized: "完成滚动截图"))
        finishButton.setAccessibilityHelp(String(localized: "结束采集并拼接当前内容"))
        addSubview(finishButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "滚动截图采集"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(progress: ScrollCaptureProgress) {
        if case .lengthLimitReached = progress.warning {
            detailLabel.stringValue = String(localized: "已达到长度上限，请完成当前截图。")
        } else if case .memoryLimitReached = progress.warning {
            detailLabel.stringValue = String(localized: "已达到内存上限，请完成当前截图。")
        } else if progress.warning != nil {
            detailLabel.stringValue = String(localized: "滚动过快，无法稳定拼接，请减慢滚动速度。")
        } else {
            detailLabel.stringValue = screenProgressText(for: progress)
        }
        detailLabel.setAccessibilityLabel(detailLabel.stringValue)
        needsLayout = true
    }

    private func screenProgressText(for progress: ScrollCaptureProgress) -> String {
        switch ScrollCaptureProgressCopy.screenCount(
            outputHeightPixels: progress.outputHeightPixels,
            viewportHeightPixels: progress.viewportHeightPixels
        ) {
        case .halfScreen:
            return String(localized: "已采集半屏 · 完成后按 Return")
        case .exactScreens(let count):
            return String(format: String(localized: "已采集 %d 屏 · 完成后按 Return"), count)
        case .approximateScreens(let count):
            return String(format: String(localized: "已采集约 %.1f 屏 · 完成后按 Return"), count)
        case nil:
            return String(localized: "滚动内容，完成后按 Return")
        }
    }

    @objc private func finish() {
        onFinish()
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let width = min(maxWidth, max(360, titleLabel.intrinsicContentSize.width + 100))
        let textWidth = max(1, width - 104)
        let textHeight = (detailLabel.stringValue as NSString).boundingRect(
            with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: detailLabel.font!]).height
        return CGSize(width: width, height: max(72, ceil(textHeight) + 44))
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        finishButton.frame = CGRect(x: bounds.maxX - 76, y: (bounds.height - 28) / 2, width: 60, height: 28)
        titleLabel.frame = CGRect(x: 14, y: bounds.height - 30, width: max(1, bounds.width - 104), height: 18)
        detailLabel.frame = CGRect(x: 14, y: 12, width: max(1, bounds.width - 104), height: max(18, bounds.height - 44))
    }
}
