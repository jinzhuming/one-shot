import AppKit
import AVKit
import ShotKit

@MainActor
final class RecordingPreviewController: NSObject, NSWindowDelegate {
    static let shared = RecordingPreviewController()

    private static let previewSize = CGSize(width: 360, height: 240)
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
                SaveLocationPresenter.showCopied(on: result.screen)
            },
            onSave: { [weak self] in self?.save(result.url) },
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
        window.backgroundColor = .black
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
    private let playerView = AVPlayerView()
    private let actionBar = NSVisualEffectView()
    private let copyButton = NSButton(title: String(localized: "复制"), target: nil, action: nil)
    private let saveButton = NSButton(title: String(localized: "保存…"), target: nil, action: nil)
    private let closeButton = NSButton(title: String(localized: "关闭"), target: nil, action: nil)
    private let player: AVPlayer
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onClose: () -> Void
    private var trackingArea: NSTrackingArea?

    init(url: URL, onCopy: @escaping () -> Void, onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.player = AVPlayer(url: url)
        self.onCopy = onCopy
        self.onSave = onSave
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        actionBar.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        actionBar.isHidden = true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "录制视频预览"))

        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)

        actionBar.material = .hudWindow
        actionBar.blendingMode = .withinWindow
        actionBar.state = .active
        actionBar.appearance = NSAppearance(named: .vibrantDark)
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.isHidden = true
        addSubview(actionBar)

        configure(copyButton, action: #selector(copyVideo), help: String(localized: "复制视频文件"))
        configure(saveButton, action: #selector(saveVideo), help: String(localized: "将视频另存到其他位置"))
        configure(closeButton, action: #selector(closePreview), help: String(localized: "关闭视频预览"))

        actionBar.addSubview(copyButton)
        actionBar.addSubview(saveButton)
        actionBar.addSubview(closeButton)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 42),
            copyButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 10),
            copyButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            saveButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor)
        ])
    }

    private func configure(_ button: NSButton, action: Selector, help: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.contentTintColor = .white
        button.toolTip = help
        button.setAccessibilityLabel(button.title)
        button.setAccessibilityHelp(help)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func copyVideo() {
        onCopy()
    }

    @objc private func saveVideo() {
        onSave()
    }

    @objc private func closePreview() {
        onClose()
    }
}
