import AppKit
import AVKit
import ShotKit

@MainActor
final class RecordingPreviewController: NSObject, NSWindowDelegate {
    static let shared = RecordingPreviewController()

    private static let previewSize = CGSize(width: 380, height: 284)
    private var windows: [UUID: RecordingPreviewWindow] = [:]
    private var order: [UUID] = []
    private var screenParametersObserver: NSObjectProtocol?

    override init() {
        super.init()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.relayoutForCurrentScreens()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func present(_ result: RecordingResult) {
        let id = UUID()
        let view = RecordingPreviewView(
            url: result.url,
            onCopy: { [weak self] in
                guard VideoExporter.copyToClipboard(result.url) else {
                    self?.presentError(VideoExporter.ExportError.clipboardFailed)
                    return
                }
                SaveLocationPresenter.showCopied(
                    message: String(localized: "视频已复制到剪贴板"),
                    on: result.screen
                )
            },
            onSave: { [weak self] in self?.save(result.url) },
            onReveal: {
                NSWorkspace.shared.activateFileViewerSelecting([result.url])
            },
            onClose: { [weak self] in self?.close(id: id) }
        )
        let window = RecordingPreviewWindow(
            contentRect: NSRect(origin: .zero, size: Self.previewSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.recordingID = id
        window.onRequestClose = { [weak self] in
            self?.close(id: id)
        }
        window.displayID = result.screen.displayID
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .none
        window.contentView = view
        window.delegate = self

        windows[id] = window
        order.insert(id, at: 0)
        relayout()
        window.orderFrontRegardless()
        view.startPlayback()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? RecordingPreviewWindow,
              let id = window.recordingID else { return }
        (window.contentView as? RecordingPreviewView)?.stopPlayback()
        window.contentView = nil
        windows.removeValue(forKey: id)
        order.removeAll { $0 == id }
        relayout()
    }

    private func close(id: UUID) {
        windows[id]?.close()
    }

    private func relayout() {
        let grouped = Dictionary(grouping: order) { id in
            windows[id]?.displayID ?? 0
        }
        for (displayID, ids) in grouped {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { continue }
            let frames = RecordingLayout.previewFrames(
                count: ids.count,
                windowSize: Self.previewSize,
                visibleFrame: screen.visibleFrame
            )
            for (index, id) in ids.enumerated() {
                windows[id]?.setFrame(frames[index], display: true)
            }
        }
    }

    private func relayoutForCurrentScreens() {
        let screens = NSScreen.screens
        guard let fallback = screens.first else { return }
        for window in windows.values where !screens.contains(where: { $0.displayID == window.displayID }) {
            window.displayID = fallback.displayID
        }
        relayout()
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }

    private func save(_ sourceURL: URL) {
        guard let destinationURL = VideoExporter.promptSaveURL(sourceURL: sourceURL) else { return }
        Task { @MainActor in
            do {
                try await VideoExporter.copy(sourceURL, to: destinationURL)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

final class RecordingPreviewWindow: NSWindow {
    var recordingID: UUID?
    var displayID: CGDirectDisplayID = 0
    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }
}

final class RecordingPreviewView: NSView {
    private let effectView = NSVisualEffectView()
    private let playerView = AVPlayerView()
    private let actionGroup = NSStackView()
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let revealButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let player: AVPlayer
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onReveal: () -> Void
    private let onClose: () -> Void

    init(
        url: URL,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.player = AVPlayer(url: url)
        self.onCopy = onCopy
        self.onSave = onSave
        self.onReveal = onReveal
        self.onClose = onClose
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startPlayback() {
        player.play()
    }

    func stopPlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        player.pause()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .vibrantDark)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "录制视频预览"))

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)

        configure(copyButton, title: String(localized: "复制"), action: #selector(copyVideo))
        configure(saveButton, title: String(localized: "保存"), action: #selector(saveVideo))
        configure(revealButton, title: String(localized: "在访达中显示"), action: #selector(revealVideo))
        configure(closeButton, title: String(localized: "关闭"), action: #selector(closePreview))

        actionGroup.orientation = .horizontal
        actionGroup.alignment = .centerY
        actionGroup.spacing = 8
        actionGroup.addArrangedSubview(copyButton)
        actionGroup.addArrangedSubview(saveButton)
        actionGroup.addArrangedSubview(revealButton)
        actionGroup.addArrangedSubview(closeButton)
        actionGroup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionGroup)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            playerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            playerView.bottomAnchor.constraint(equalTo: actionGroup.topAnchor, constant: -8),
            actionGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            actionGroup.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            actionGroup.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            actionGroup.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func copyVideo() {
        onCopy()
    }

    @objc private func saveVideo() {
        onSave()
    }

    @objc private func revealVideo() {
        onReveal()
    }

    @objc private func closePreview() {
        onClose()
    }
}
