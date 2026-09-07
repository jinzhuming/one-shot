import AppKit

@MainActor
final class RecordingControlBarController: NSObject {
    private static let size = NSSize(width: 420, height: 58)

    private var window: RecordingControlBarWindow?
    private var view: RecordingControlBarView?
    private var displayID: CGDirectDisplayID?
    private var timer: Timer?
    private var elapsedProvider: (() -> TimeInterval?)?
    private var screenParametersObserver: NSObjectProtocol?

    override init() {
        super.init()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.relayout()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func present(
        on screen: NSScreen,
        state: RecordingState,
        elapsedProvider: @escaping () -> TimeInterval?,
        onPause: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()
        self.displayID = screen.displayID
        self.elapsedProvider = elapsedProvider

        let barView = RecordingControlBarView(
            onPause: onPause,
            onStop: onStop,
            onCancel: onCancel
        )
        barView.update(state: state, elapsed: elapsedProvider())

        let barWindow = RecordingControlBarWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        barWindow.onCancel = onCancel
        barWindow.isOpaque = false
        barWindow.backgroundColor = .clear
        barWindow.hasShadow = true
        barWindow.isRestorable = false
        barWindow.level = CaptureWindowLevels.modeBar
        barWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        barWindow.isReleasedWhenClosed = false
        barWindow.sharingType = .none
        barWindow.animationBehavior = .none
        barWindow.contentView = barView

        self.window = barWindow
        self.view = barView
        position(on: screen)
        barWindow.orderFrontRegardless()

        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(updateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(state: RecordingState, elapsed: TimeInterval?) {
        view?.update(state: state, elapsed: elapsed)
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
        view = nil
        displayID = nil
        elapsedProvider = nil
    }

    @objc private func updateTimer() {
        view?.update(
            state: view?.state ?? .idle,
            elapsed: elapsedProvider?()
        )
    }

    private func position(on screen: NSScreen) {
        guard let window else { return }
        let visibleFrame = screen.visibleFrame
        let horizontalInset: CGFloat = 12
        let maximumX = max(
            visibleFrame.minX + horizontalInset,
            visibleFrame.maxX - Self.size.width - horizontalInset
        )
        let x = min(
            max(visibleFrame.minX + horizontalInset, visibleFrame.midX - Self.size.width / 2),
            maximumX
        )
        let y = visibleFrame.minY + 18
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func relayout() {
        guard let displayID,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return
        }
        position(on: screen)
    }
}

final class RecordingControlBarWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class RecordingControlBarView: NSView {
    private let effectView = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let pauseButton = NSButton(title: "", target: nil, action: nil)
    private let stopButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let stackView = NSStackView()

    private let onPause: () -> Void
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private(set) var state: RecordingState = .idle

    init(
        onPause: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPause = onPause
        self.onStop = onStop
        self.onCancel = onCancel
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: RecordingState, elapsed: TimeInterval?) {
        self.state = state
        statusLabel.stringValue = statusText(for: state)
        elapsedLabel.stringValue = formatElapsed(elapsed ?? 0)
        elapsedLabel.isHidden = state == .stopping

        switch state {
        case .recording:
            configurePauseButton(
                title: String(localized: "暂停"),
                symbolName: "pause.fill",
                help: String(localized: "暂停录屏"),
                enabled: true
            )
        case .paused:
            configurePauseButton(
                title: String(localized: "继续"),
                symbolName: "play.fill",
                help: String(localized: "继续录屏"),
                enabled: true
            )
        case .starting, .pausing, .resuming:
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            cancelButton.isEnabled = true
        case .stopping:
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            cancelButton.isEnabled = false
        default:
            pauseButton.isEnabled = false
            stopButton.isEnabled = false
            cancelButton.isEnabled = false
        }

        setAccessibilityValue(statusText(for: state))
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
    }

    override func isAccessibilityElement() -> Bool { false }

    @objc private func pausePressed() {
        onPause()
    }

    @objc private func stopPressed() {
        onStop()
    }

    @objc private func cancelPressed() {
        onCancel()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.isHidden = HUDChrome.reduceTransparency
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        if HUDChrome.reduceTransparency {
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        }

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.setAccessibilityLabel(String(localized: "录屏状态"))
        statusLabel.setAccessibilityRole(.staticText)

        elapsedLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        elapsedLabel.textColor = .white.withAlphaComponent(0.86)
        elapsedLabel.alignment = .right
        elapsedLabel.setAccessibilityLabel(String(localized: "录屏时长"))
        elapsedLabel.setAccessibilityRole(.staticText)

        configure(
            pauseButton,
            action: #selector(pausePressed),
            title: String(localized: "暂停"),
            symbolName: "pause.fill",
            help: String(localized: "暂停录屏")
        )
        configure(
            stopButton,
            action: #selector(stopPressed),
            title: String(localized: "停止"),
            symbolName: "stop.fill",
            help: String(localized: "停止并保存录屏")
        )
        configure(
            cancelButton,
            action: #selector(cancelPressed),
            title: String(localized: "取消"),
            symbolName: "xmark",
            help: String(localized: "取消录屏并删除当前文件")
        )

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(elapsedLabel)
        stackView.addArrangedSubview(pauseButton)
        stackView.addArrangedSubview(stopButton)
        stackView.addArrangedSubview(cancelButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            elapsedLabel.widthAnchor.constraint(equalToConstant: 42)
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "录屏控制"))
    }

    private func configure(
        _ button: NSButton,
        action: Selector,
        title: String,
        symbolName: String,
        help: String
    ) {
        button.target = self
        button.action = action
        button.title = title
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: help)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.contentTintColor = .white
        button.toolTip = help
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(help)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePauseButton(
        title: String,
        symbolName: String,
        help: String,
        enabled: Bool
    ) {
        pauseButton.title = title
        pauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: help)
        pauseButton.setAccessibilityLabel(title)
        pauseButton.setAccessibilityHelp(help)
        pauseButton.isEnabled = enabled
    }

    private func statusText(for state: RecordingState) -> String {
        switch state {
        case .recording:
            return String(localized: "正在录制")
        case .paused:
            return String(localized: "已暂停")
        case .starting, .resuming:
            return String(localized: "正在准备录屏…")
        case .pausing:
            return String(localized: "正在暂停…")
        case .stopping:
            return String(localized: "正在保存录屏…")
        default:
            return String(localized: "录屏")
        }
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
