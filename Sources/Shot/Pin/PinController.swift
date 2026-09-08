import AppKit
import ShotKit
import SwiftUI

@MainActor
final class PinController {
    static let shared = PinController()

    private var windows: [UUID: PinWindow] = [:]

    func present(_ image: NSImage, on screen: NSScreen?) {
        let id = UUID()
        let view = PinContentView(
            image: image,
            onCopy: {
                if ImageExporter.copyToClipboard(image) {
                    SaveLocationPresenter.showCopied()
                }
            },
            onSave: { [weak self] in
                self?.save(image)
            },
            onClose: { [weak self] in
                self?.close(id)
            }
        )
        let size = PinLayout.windowSize(for: image.size, visibleFrame: screen?.visibleFrame ?? .zero)
        let window = PinWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.pinID = id
        window.onRequestClose = { [weak self] in self?.close(id) }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .none
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
        ScreenshotHistoryStore.add(image)
    }

    func close(_ id: UUID) {
        windows[id]?.close()
        windows[id] = nil
    }

    private func save(_ image: NSImage) {
        guard let url = ImageExporter.destinationURL(settings: AppSettings.shared) else { return }
        Task { @MainActor in
            do {
                try await ImageExporter.save(image, format: AppSettings.shared.saveFormat, to: url)
                SaveLocationPresenter.showSaved(at: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

enum PinLayout {
    static func windowSize(for imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let maxWidth = max(240, min(imageSize.width, visibleFrame.width > 0 ? visibleFrame.width * 0.45 : 480))
        let scale = imageSize.width > 0 ? maxWidth / imageSize.width : 1
        let imageHeight = max(120, imageSize.height * scale)
        return CGSize(width: maxWidth, height: imageHeight + 44)
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
}

final class PinWindow: NSPanel {
    var pinID: UUID?
    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }
}

private final class PinContentView: NSView {
    private let effectView = NSVisualEffectView()
    private let imageView = NSImageView()
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onClose: () -> Void

    init(
        image: NSImage,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onSave = onSave
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        addSubview(effectView)

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        configure(copyButton, title: String(localized: "复制"), action: #selector(copyImage))
        configure(saveButton, title: String(localized: "保存"), action: #selector(saveImage))
        configure(closeButton, title: String(localized: "关闭"), action: #selector(closePin))
        addSubview(copyButton)
        addSubview(saveButton)
        addSubview(closeButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.window)
        setAccessibilityLabel(String(localized: "钉图"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        imageView.frame = CGRect(x: 0, y: 44, width: bounds.width, height: max(0, bounds.height - 44))
        let buttonWidth: CGFloat = 72
        copyButton.frame = CGRect(x: 10, y: 8, width: buttonWidth, height: 28)
        saveButton.frame = CGRect(x: 88, y: 8, width: buttonWidth, height: 28)
        closeButton.frame = CGRect(x: bounds.width - 82, y: 8, width: 72, height: 28)
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
    }

    @objc private func copyImage() { onCopy() }
    @objc private func saveImage() { onSave() }
    @objc private func closePin() { onClose() }
}
