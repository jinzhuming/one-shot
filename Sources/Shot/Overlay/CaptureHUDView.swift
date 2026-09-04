import AppKit

final class CaptureHUDView: NSView {
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            label.stringValue = text
            invalidateIntrinsicContentSize()
            needsLayout = true
            isHidden = text.isEmpty
        }
    }

    private let effectView = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        guard !text.isEmpty else { return .zero }
        let size = label.intrinsicContentSize
        return NSSize(width: ceil(size.width) + 16, height: 24)
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        label.frame = bounds.insetBy(dx: 8, dy: 2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { !text.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role { .staticText }
    override func accessibilityLabel() -> String? {
        text.isEmpty ? nil : String(localized: "选区尺寸 \(text)")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)

        let reduce = HUDChrome.reduceTransparency
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.isHidden = reduce
        addSubview(effectView)

        if reduce {
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
}
