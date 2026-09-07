import AppKit
import ShotKit

@MainActor
final class ScrollCaptureHUD {
    private var panel: NSPanel?
    private var contentView: ScrollCaptureHUDView?

    func show(on screen: NSScreen, onFinish: @escaping @MainActor () -> Void) {
        hide()

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
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 16
        ))
        panel.orderFrontRegardless()
        self.panel = panel
        self.contentView = view
    }

    func update(progress: ScrollCaptureProgress) {
        contentView?.update(progress: progress)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        contentView = nil
    }
}

@MainActor
private final class ScrollCaptureHUDView: NSView {
    private let effectView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: String(localized: "正在采集滚动截图…"))
    private let detailLabel = NSTextField(labelWithString: String(localized: "滚动内容，完成后按 Return"))
    private let finishButton = NSButton(title: String(localized: "完成"), target: nil, action: nil)
    private let onFinish: @MainActor () -> Void

    init(frame frameRect: NSRect, onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
        super.init(frame: frameRect)
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
        titleLabel.textColor = .white
        titleLabel.setAccessibilityLabel(String(localized: "正在采集滚动截图"))
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.75)
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
        let height = String(progress.outputHeightPixels)
        if case .lengthLimitReached = progress.warning {
            detailLabel.stringValue = String(localized: "已达到长度上限，请完成当前截图。")
        } else if case .memoryLimitReached = progress.warning {
            detailLabel.stringValue = String(localized: "已达到内存上限，请完成当前截图。")
        } else if progress.warning != nil {
            detailLabel.stringValue = String(localized: "滚动过快，无法稳定拼接，请减慢滚动速度。")
        } else {
            detailLabel.stringValue = String(
                format: String(localized: "已采集 %@ 像素 · 完成后按 Return"),
                height
            )
        }
        detailLabel.setAccessibilityLabel(detailLabel.stringValue)
        needsLayout = true
    }

    @objc private func finish() {
        onFinish()
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        finishButton.frame = CGRect(x: bounds.maxX - 72, y: 16, width: 60, height: 28)
        titleLabel.frame = CGRect(x: 14, y: 34, width: bounds.width - 98, height: 18)
        detailLabel.frame = CGRect(x: 14, y: 12, width: bounds.width - 98, height: 18)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if HUDChrome.reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }
    }
}
