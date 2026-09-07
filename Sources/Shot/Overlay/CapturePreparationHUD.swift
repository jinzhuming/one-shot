import AppKit
import ShotKit

@MainActor
final class CapturePreparationHUD {
    private var panel: NSPanel?

    func show() {
        guard panel == nil,
              let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation)
        else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 184, height: 36),
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

        let view = CapturePreparationView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = view
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(
            x: mouse.x - panel.frame.width / 2,
            y: mouse.y - panel.frame.height - 18
        )
        panel.setFrameOrigin(
            RectMath.clampedOrigin(
                origin,
                size: panel.frame.size,
                in: screen.visibleFrame.insetBy(dx: 8, dy: 8)
            )
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

@MainActor
private final class CapturePreparationView: NSView {
    private let effectView = NSVisualEffectView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: String(localized: "正在准备截图…"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        addSubview(effectView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        spinner.setAccessibilityLabel(String(localized: "正在准备截图"))
        addSubview(spinner)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.setAccessibilityLabel(String(localized: "正在准备截图"))
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "正在准备截图"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        spinner.frame = CGRect(x: 12, y: 10, width: 16, height: 16)
        label.frame = CGRect(x: 36, y: 8, width: bounds.width - 46, height: 20)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if HUDChrome.reduceTransparency {
            effectView.isHidden = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }
    }
}
