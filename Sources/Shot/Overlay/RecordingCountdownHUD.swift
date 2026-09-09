import AppKit
import ShotKit

@MainActor
final class RecordingCountdownHUD {
    private var panel: NSPanel?

    func show(seconds: Int, on screen: NSScreen) {
        hide()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 88),
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

        let view = RecordingCountdownView(frame: panel.contentRect(forFrameRect: panel.frame))
        view.update(seconds)
        panel.contentView = view
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(
            x: visible.midX - 44,
            y: visible.midY - 44
        ))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(_ seconds: Int) {
        (panel?.contentView as? RecordingCountdownView)?.update(seconds)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

private final class RecordingCountdownView: NSView {
    let label = NSTextField(labelWithString: "")
    private let effectView = HUDMaterialView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = InterfaceMetrics.panelRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        addSubview(effectView)
        label.font = .monospacedDigitSystemFont(ofSize: 36, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func update(_ seconds: Int) {
        label.stringValue = "\(seconds)"
        setAccessibilityLabel(String(localized: "倒计时 \(seconds) 秒"))
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        label.frame = bounds
    }
}
