import AppKit
import ShotKit
import SwiftUI

@MainActor
final class EditorPresenter {
    var onFinish: (() -> Void)?

    private var panel: NSWindow?
    private var session: EditSession?
    private var keyMonitor: Any?
    private var overlay: OverlayController?
    private var saveTask: Task<Void, Never>?
    private var outputLifetime = OperationLifetime()
    private let output: EditorOutputService

    init(output: EditorOutputService? = nil) { self.output = output ?? EditorOutputService() }
    private var presentationScreen: NSScreen?
    private var chromeSuspended = false

    func presentInPlace(result: CaptureResult, overlay: OverlayController) {
        self.overlay = overlay
        overlay.enterDimOnly()
        present(
            result: result,
            preferredImageSize: result.rect.size,
            originForImage: result.rect,
            screen: result.screen,
            presentationStyle: .inPlace
        )
    }

    func presentCentered(result: CaptureResult, overlay: OverlayController) {
        self.overlay = overlay
        overlay.dismiss()
        present(
            result: result,
            preferredImageSize: result.image.size,
            originForImage: nil,
            screen: result.screen,
            presentationStyle: .windowed
        )
    }

    func restoreAnnotation(_ session: EditSession, on screen: NSScreen) {
        overlay = nil
        present(
            session: session,
            preferredImageSize: session.document.baseImage.size,
            originForImage: nil,
            screen: screen,
            presentationStyle: .windowed
        )
    }

    func dismiss() {
        chromeSuspended = false
        AnnotationColorPickerController.dismiss()
        outputLifetime.invalidate()
        saveTask?.cancel()
        saveTask = nil
        session?.endExport()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let panel {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        self.panel = nil
        session = nil
        presentationScreen = nil
        overlay?.dismiss()
        overlay = nil
        NSCursor.arrow.set()
        onFinish?()
    }

    private func present(
        result: CaptureResult,
        preferredImageSize: CGSize,
        originForImage: CGRect?,
        screen: NSScreen,
        presentationStyle: EditorPresentationStyle
    ) {
        present(
            session: EditSession(image: result.image),
            preferredImageSize: preferredImageSize,
            originForImage: originForImage,
            screen: screen,
            presentationStyle: presentationStyle
        )
    }

    private func present(
        session: EditSession,
        preferredImageSize: CGSize,
        originForImage: CGRect?,
        screen: NSScreen,
        presentationStyle: EditorPresentationStyle
    ) {
        presentationScreen = screen
        session.onCanvasSizeChange = { [weak self] in
            self?.relayoutForCurrentImage()
        }
        self.session = session

        let vis = screen.visibleFrame
        let styleMask: NSWindow.StyleMask = presentationStyle == .windowed
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.borderless, .fullSizeContentView]
        let estimatedToolbar = CGSize(
            width: EditorLayout.minContentWidth,
            height: EditorLayout.estimatedToolbarHeight
        )
        var arrangement: EditorArrangement
        var windowedLayout: EditorWindowLayout?
        var windowFrame: CGRect
        if presentationStyle == .windowed {
            let chrome = Self.windowChromeSize(for: styleMask)
            let maxContentSize = CGSize(
                width: max(1, vis.width - 16 - chrome.width),
                height: max(1, vis.height - 16 - chrome.height)
            )
            let initialContentSize = EditorLayout.windowedInitialContentSize(
                imageSize: preferredImageSize,
                toolbarSize: estimatedToolbar,
                maxContentSize: maxContentSize
            )
            let layout = EditorLayout.windowed(
                imageSize: preferredImageSize,
                toolbarSize: estimatedToolbar,
                contentSize: initialContentSize
            )
            windowedLayout = layout
            arrangement = Self.arrangement(for: layout)
            windowFrame = Self.centeredWindowFrame(
                contentSize: layout.contentSize,
                styleMask: styleMask,
                visibleFrame: vis
            )
        } else {
            arrangement = Self.arrangement(
                preferredImageSize: preferredImageSize,
                originForImage: originForImage,
                visibleFrame: vis,
                toolbarSize: estimatedToolbar,
                center: false
            )
            windowFrame = arrangement.windowFrame
        }

        if let existing = panel {
            AnnotationColorPickerController.dismiss()
            existing.orderOut(nil)
            existing.contentView = nil
            existing.close()
            panel = nil
        }

        let content = EditorChromeView(
            session: session,
            arrangement: arrangement,
            presentationStyle: presentationStyle,
            windowedLayout: windowedLayout,
            onCopy: { [weak self] in self?.copyAndFinish() },
            onSave: { [weak self] in self?.saveAndFinish() },
            onPin: { [weak self] in self?.pinAndFinish() },
            onOCR: { [weak self] in self?.ocrFromEditor() },
            onClose: { [weak self] in self?.closeFromToolbar() }
        )
        content.frame = NSRect(origin: .zero, size: presentationStyle == .windowed
            ? (windowedLayout?.contentSize ?? .zero)
            : arrangement.windowFrame.size)
        content.autoresizingMask = [.width, .height]

        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.onRequestClose = { [weak self] in self?.closeFromWindow() }
        window.onRequestCancel = { [weak self] in self?.cancelOrDismissFromWindow() }
        window.isOpaque = presentationStyle == .windowed
        window.backgroundColor = presentationStyle == .windowed
            ? NSColor.windowBackgroundColor
            : NSColor.clear
        window.hasShadow = true
        window.acceptsMouseMovedEvents = true
        window.level = presentationStyle == .windowed ? .normal : CaptureWindowLevels.editor
        window.collectionBehavior = presentationStyle == .windowed
            ? [.moveToActiveSpace, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.sharingType = .none
        if presentationStyle == .windowed {
            window.title = String(localized: "Shot 标注")
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
        }
        window.contentView = content
        window.setFrame(windowFrame, display: false)
        content.layoutSubtreeIfNeeded()

        let measured = content.toolbarFittingSize
        if presentationStyle == .windowed {
            let chrome = Self.windowChromeSize(for: styleMask)
            let maxContentSize = CGSize(
                width: max(1, vis.width - 16 - chrome.width),
                height: max(1, vis.height - 16 - chrome.height)
            )
            let contentSize = EditorLayout.windowedInitialContentSize(
                imageSize: preferredImageSize,
                toolbarSize: measured,
                maxContentSize: maxContentSize
            )
            let layout = EditorLayout.windowed(
                imageSize: preferredImageSize,
                toolbarSize: measured,
                contentSize: contentSize
            )
            windowedLayout = layout
            arrangement = Self.arrangement(for: layout)
            content.apply(layout)
            windowFrame = Self.centeredWindowFrame(
                contentSize: layout.contentSize,
                styleMask: styleMask,
                visibleFrame: vis
            )
            window.minSize = Self.windowFrameSize(
                forContentSize: CGSize(
                    width: min(maxContentSize.width, max(EditorLayout.minContentWidth, measured.width)),
                    height: min(
                        maxContentSize.height,
                        measured.height
                            + EditorLayout.windowedToolbarGap
                            + EditorLayout.windowedMinimumWorkspaceHeight
                            + EditorLayout.windowedWorkspacePadding * 2
                    )
                ),
                styleMask: styleMask
            )
        } else if abs(measured.width - estimatedToolbar.width) > 1
                    || abs(measured.height - estimatedToolbar.height) > 1 {
            arrangement = Self.arrangement(
                preferredImageSize: preferredImageSize,
                originForImage: originForImage,
                visibleFrame: vis,
                toolbarSize: measured,
                center: false
            )
            content.apply(arrangement)
            windowFrame = arrangement.windowFrame
        }

        if presentationStyle == .inPlace, !arrangement.keepsCaptureAligned {
            overlay?.clearSelectionHole()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.setFrame(windowFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        // Activation can race with the app that was just captured. Reassert
        // the editor's front position after activation so the first editing
        // gesture cannot land on a window from that app.
        window.orderFrontRegardless()
        panel = window
        installKeyMonitor()
    }

    private static func arrangement(
        preferredImageSize: CGSize,
        originForImage: CGRect?,
        visibleFrame: CGRect,
        toolbarSize: CGSize,
        center: Bool
    ) -> EditorArrangement {
        if !center, let captureRect = originForImage {
            return EditorLayout.inPlace(
                captureRect: captureRect,
                toolbarSize: toolbarSize,
                visibleFrame: visibleFrame
            )
        }
        return EditorLayout.centered(
            imageSize: preferredImageSize,
            toolbarSize: toolbarSize,
            visibleFrame: visibleFrame
        )
    }

    private static func arrangement(for layout: EditorWindowLayout) -> EditorArrangement {
        EditorArrangement(
            windowFrame: CGRect(origin: .zero, size: layout.contentSize),
            canvasFrame: layout.canvasFrame,
            toolbarFrame: layout.toolbarFrame,
            imageSize: layout.imageSize,
            toolbarAnchor: .above,
            keepsCaptureAligned: false
        )
    }

    private static func windowChromeSize(for styleMask: NSWindow.StyleMask) -> CGSize {
        let contentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let frameRect = NSWindow.frameRect(forContentRect: contentRect, styleMask: styleMask)
        return CGSize(
            width: max(0, frameRect.width - contentRect.width),
            height: max(0, frameRect.height - contentRect.height)
        )
    }

    private static func windowFrameSize(
        forContentSize contentSize: CGSize,
        styleMask: NSWindow.StyleMask
    ) -> CGSize {
        let frame = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask
        )
        return frame.size
    }

    private static func centeredWindowFrame(
        contentSize: CGSize,
        styleMask: NSWindow.StyleMask,
        visibleFrame: CGRect
    ) -> CGRect {
        let frameSize = windowFrameSize(forContentSize: contentSize, styleMask: styleMask)
        let preferred = CGPoint(
            x: visibleFrame.midX - frameSize.width / 2,
            y: visibleFrame.midY - frameSize.height / 2
        )
        let origin = EditorLayout.clampedOrigin(
            windowSize: frameSize,
            preferred: preferred,
            visibleFrame: visibleFrame,
            margin: 8
        )
        return CGRect(origin: origin, size: frameSize)
    }

    private func installKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, let panel = self.panel,
                  event.window === panel || NSApp.keyWindow === panel else { return event }
            if event.keyCode == 49 {
                (self.panel?.contentView as? EditorChromeView)?.setSpaceHeld(event.type == .keyDown)
                return event
            }
            let command = event.modifierFlags.contains(.command)
            if command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                self.closeFromWindow()
                return nil
            }
            if self.session?.isEditingText == true {
                if event.keyCode == 53 {
                    _ = self.session?.cancelTextEditing()
                    return nil
                }
                if command, event.charactersIgnoringModifiers?.lowercased() == "c" {
                    self.copyAndFinish()
                    return nil
                }
                if command, event.charactersIgnoringModifiers?.lowercased() == "s" {
                    self.saveAndFinish()
                    return nil
                }
                return event
            }
            if self.isEditingFieldEditor(event) {
                if event.keyCode == 53 {
                    _ = self.session?.cancelTextEditing()
                    return nil
                }
                return event
            }
            if event.keyCode == 53 {
                self.requestDismissDiscardingAnnotations()
                return nil
            }
            if !command, (event.keyCode == 51 || event.keyCode == 117) {
                self.session?.deleteSelection()
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "d" {
                self.session?.duplicateSelection()
                return nil
            }
            if !command, (event.keyCode == 36 || event.keyCode == 76) {
                self.copyAndFinish()
                return nil
            }
            if !command, let tool = AnnotationToolID.fromShortcutKeyCode(event.keyCode) {
                self.session?.selectedTool = tool
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.copyAndFinish()
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "s" {
                self.saveAndFinish()
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "z" {
                if event.modifierFlags.contains(.shift) {
                    self.session?.redo()
                } else {
                    self.session?.undo()
                }
                return nil
            }
            return event
        }
    }

    private func isEditingFieldEditor(_ event: NSEvent) -> Bool {
        guard let first = panel?.firstResponder else { return false }
        if first is NSTextView || first is NSTextField { return true }
        return false
    }

    @MainActor
    private func commitPendingText() {
        guard session?.isEditingText == true else { return }
        (panel?.contentView as? EditorChromeView)?.commitPendingText()
    }

    @MainActor
    private func closeFromToolbar() {
        commitPendingText()
        requestDismissDiscardingAnnotations()
    }

    @MainActor
    private func closeFromWindow() {
        closeFromToolbar()
    }

    @MainActor
    private func cancelOrDismissFromWindow() {
        if session?.cancelTextEditing() == true {
            return
        }
        requestDismissDiscardingAnnotations()
    }

    @MainActor
    private func requestDismissDiscardingAnnotations() {
        if session?.document.elements.isEmpty == false {
            let alert = NSAlert()
            alert.messageText = String(localized: "放弃标注？")
            alert.informativeText = String(localized: "关闭后未复制或保存的标注会丢失。")
            alert.addButton(withTitle: String(localized: "放弃"))
            alert.addButton(withTitle: String(localized: "取消"))
            alert.alertStyle = .warning
            alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }
        dismiss()
    }

    private func copyAndFinish() { performOutput(.copy) }
    private func saveAndFinish() { performOutput(.save) }
    private func pinAndFinish() { performOutput(.pin) }
    private func ocrFromEditor() { performOutput(.ocr) }

    private func performOutput(_ action: EditorOutputAction) {
        commitPendingText()
        guard let session, session.beginExport() else { return }
        let settings = AppSettings.shared
        let format = settings.saveFormat
        let copyOnComplete = settings.copyOnComplete
        let destination: ImageExportDestination?
        if action == .save {
            guard let selected = ImageExporter.destination(settings: settings) else {
                session.endExport()
                return
            }
            destination = selected
        } else {
            destination = nil
        }
        guard let snapshot = AnnotationRenderSnapshot(document: session.document) else {
            session.endExport()
            presentErrorPreservingEditor(ImageExporter.ExportError.encodingFailed)
            return
        }
        let screen = presentationScreen
        let token = outputLifetime.begin()
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self else { session.endExport(); return }
            defer {
                if self.outputLifetime.finish(token) {
                    session.endExport()
                    self.saveTask = nil
                }
            }
            do {
                let result = try await self.output.perform(
                    action, snapshot: snapshot, format: format, destination: destination
                )
                guard !Task.isCancelled, self.outputLifetime.contains(token), self.session === session else { return }
                let image = result.image
                switch action {
                case .copy:
                    guard ImageExporter.copyToClipboard(image) else { throw ImageExporter.ExportError.clipboardFailed }
                    ScreenshotHistoryStore.add(image)
                    self.dismiss()
                    SaveLocationPresenter.showCopied(on: screen)
                case .save:
                    guard let url = result.url else { return }
                    ScreenshotHistoryStore.add(image)
                    if copyOnComplete, !ImageExporter.copyToClipboard(image) {
                        throw ImageExporter.ExportError.savedButClipboardFailed
                    }
                    self.dismiss()
                    SaveLocationPresenter.showSaved(at: url, on: screen)
                case .pin:
                    self.dismiss()
                    PinController.shared.present(image, on: screen) { [session] in
                        guard let screen = Self.availableScreen(preferred: screen) else { return }
                        CaptureSession.shared.restoreEditorSession(session, on: screen)
                    }
                case .ocr:
                    let text = result.text ?? ""
                    if !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        guard NSPasteboard.general.setString(text, forType: .string) else {
                            throw ImageExporter.ExportError.clipboardFailed
                        }
                    }
                    ScreenshotHistoryStore.add(image)
                    SaveLocationPresenter.showCopied(
                        message: text.isEmpty ? String(localized: "未识别到文字") : String(localized: "已复制识别文字"),
                        on: screen
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.outputLifetime.contains(token), self.session === session else { return }
                Diagnostics.exports.error("Editor output failed")
                self.presentErrorPreservingEditor(error)
            }
        }
    }

    private static func availableScreen(preferred: NSScreen?) -> NSScreen? {
        if let preferred, let screen = NSScreen.screens.first(where: { $0.displayID == preferred.displayID }) {
            return screen
        }
        return CoordinateSpace.screen(containing: NSEvent.mouseLocation) ?? NSScreen.screens.first
    }

    func suspendChrome() {
        chromeSuspended = true
        outputLifetime.invalidate()
        saveTask?.cancel()
        saveTask = nil
        session?.endExport()
        overlay?.dismiss()
        panel?.orderOut(nil)
    }

    func relayoutForCurrentScreens() {
        guard panel != nil, let screen = Self.availableScreen(preferred: presentationScreen) else { return }
        presentationScreen = screen
        relayoutForCurrentImage()
        if chromeSuspended {
            chromeSuspended = false
            panel?.orderFrontRegardless()
        }
    }

    private func relayoutForCurrentImage() {
        guard let session, let panel, let screen = presentationScreen ?? panel.screen else { return }
        let content = panel.contentView as? EditorChromeView
        let vis = screen.visibleFrame
        let imageSize = session.document.baseImage.size
        let toolbarSize = content?.toolbarFittingSize ?? NSSize(
            width: EditorLayout.minContentWidth,
            height: EditorLayout.estimatedToolbarHeight
        )
        if panel.styleMask.contains(.titled) {
            let chrome = Self.windowChromeSize(for: panel.styleMask)
            let maxContentSize = CGSize(
                width: max(1, vis.width - 16 - chrome.width),
                height: max(1, vis.height - 16 - chrome.height)
            )
            let contentSize = EditorLayout.windowedInitialContentSize(
                imageSize: imageSize,
                toolbarSize: toolbarSize,
                maxContentSize: maxContentSize
            )
            let layout = EditorLayout.windowed(
                imageSize: imageSize,
                toolbarSize: toolbarSize,
                contentSize: contentSize
            )
            content?.apply(layout)
            let frame = Self.centeredWindowFrame(
                contentSize: layout.contentSize,
                styleMask: panel.styleMask,
                visibleFrame: vis
            )
            panel.setFrame(frame, display: true)
        } else {
            let arrangement = Self.arrangement(
                preferredImageSize: imageSize,
                originForImage: nil,
                visibleFrame: vis,
                toolbarSize: toolbarSize,
                center: true
            )
            content?.apply(arrangement)
            panel.setFrame(arrangement.windowFrame, display: true)
        }
    }

    private func presentErrorPreservingEditor(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
        alert.runModal()
    }
}

private final class EditorWindow: NSWindow {
    var onRequestClose: (() -> Void)?
    var onRequestCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        onRequestClose?()
    }

    override func cancelOperation(_ sender: Any?) {
        onRequestCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
