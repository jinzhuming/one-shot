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
    private var presentationScreen: NSScreen?

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

    func dismiss() {
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
        presentationScreen = screen
        let session = EditSession(image: result.image)
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
            scrollableCanvas: result.kind == .scrolling,
            onCopy: { [weak self] in self?.copyAndFinish() },
            onSave: { [weak self] in self?.saveAndFinish() },
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
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
                self.dismiss()
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
        dismiss()
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
        dismiss()
    }

    @MainActor
    private func copyAndFinish() {
        commitPendingText()
        guard let session, session.beginExport() else { return }
        let document = session.document
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self else {
                session.endExport()
                return
            }
            guard let image = await self.renderedImage(from: document) else {
                session.endExport()
                self.presentErrorPreservingEditor(ImageExporter.ExportError.encodingFailed)
                return
            }
            guard !Task.isCancelled, self.session === session else {
                session.endExport()
                return
            }
            let screen = self.presentationScreen
            session.endExport()
            guard ImageExporter.copyToClipboard(image) else {
                self.saveTask = nil
                self.presentErrorPreservingEditor(ImageExporter.ExportError.clipboardFailed)
                return
            }
            self.saveTask = nil
            self.dismiss()
            SaveLocationPresenter.showCopied(on: screen)
        }
    }

    private func saveAndFinish() {
        commitPendingText()
        guard let session, session.beginExport() else { return }
        let settings = AppSettings.shared
        guard let url = ImageExporter.destinationURL(settings: settings) else {
            session.endExport()
            return
        }
        let format = settings.saveFormat
        let copyOnComplete = settings.copyOnComplete
        let document = session.document
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let self else {
                session.endExport()
                return
            }
            guard let image = await self.renderedImage(from: document) else {
                session.endExport()
                self.presentErrorPreservingEditor(ImageExporter.ExportError.encodingFailed)
                return
            }
            guard !Task.isCancelled, self.session === session else {
                session.endExport()
                return
            }
            do {
                try await ImageExporter.save(image, format: format, to: url)
                guard !Task.isCancelled else {
                    session.endExport()
                    return
                }
                if copyOnComplete,
                   !ImageExporter.copyToClipboard(image) {
                    session.endExport()
                    self.saveTask = nil
                    self.presentErrorPreservingEditor(ImageExporter.ExportError.clipboardFailed)
                    return
                }
                session.endExport()
                self.saveTask = nil
                let screen = self.presentationScreen
                self.dismiss()
                SaveLocationPresenter.showSaved(at: url, on: screen)
            } catch is CancellationError {
                session.endExport()
                return
            } catch {
                guard !Task.isCancelled else {
                    session.endExport()
                    return
                }
                session.endExport()
                self.saveTask = nil
                let alert = NSAlert(error: error)
                alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
                alert.runModal()
            }
        }
    }

    private func renderedImage(from document: AnnotationDocument) async -> NSImage? {
        let imageSize = document.baseImage.size
        let snapshot = AnnotationRenderSnapshot(document: document)
        let cgImage = await Task.detached(priority: .userInitiated) {
            snapshot.renderedCGImage()
        }.value
        guard !Task.isCancelled, let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: imageSize)
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
