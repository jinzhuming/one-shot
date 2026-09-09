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

    var sampledHex: String? {
        didSet {
            guard sampledHex != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }

    private let effectView = HUDMaterialView()
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
        let swatchWidth: CGFloat = sampledHex == nil ? 0 : 22
        return NSSize(width: ceil(size.width) + 16 + swatchWidth, height: 24)
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        let swatchWidth: CGFloat = sampledHex == nil ? 0 : 18
        label.frame = CGRect(
            x: 8,
            y: 2,
            width: max(0, bounds.width - 16 - swatchWidth - (swatchWidth > 0 ? 4 : 0)),
            height: max(0, bounds.height - 4)
        )
    }

    var colorSwatchFrame: CGRect? {
        guard sampledHex != nil else { return nil }
        return CGRect(x: bounds.maxX - 8 - 18, y: 5, width: 18, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let sampledHex, let color = NSColor(hex: sampledHex), let frame = colorSwatchFrame else { return }
        let path = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
        color.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
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

        effectView.cornerRadius = InterfaceMetrics.compactPanelRadius
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        addSubview(effectView)


        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
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

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}
