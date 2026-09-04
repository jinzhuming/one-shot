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

    func presentRegion(result: CaptureResult, overlay: OverlayController) {
        self.overlay = overlay
        overlay.enterDimOnly()
        present(
            result: result,
            preferredImageSize: result.rect.size,
            originForImage: result.rect,
            screen: result.screen,
            center: false
        )
    }

    func presentFloating(result: CaptureResult, overlay: OverlayController) {
        self.overlay = overlay
        overlay.presentDimBackdrop()
        present(
            result: result,
            preferredImageSize: result.image.size,
            originForImage: nil,
            screen: result.screen,
            center: true
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
        center: Bool
    ) {
        presentationScreen = screen
        let session = EditSession(image: result.image)
        self.session = session

        let vis = screen.visibleFrame
        let estimatedToolbar = CGSize(
            width: EditorLayout.minContentWidth,
            height: EditorLayout.estimatedToolbarHeight
        )
        var arrangement = Self.arrangement(
            preferredImageSize: preferredImageSize,
            originForImage: originForImage,
            visibleFrame: vis,
            toolbarSize: estimatedToolbar,
            center: center
        )

        if let existing = panel {
            existing.orderOut(nil)
            existing.contentView = nil
            existing.close()
            panel = nil
        }

        let content = EditorChromeView(
            session: session,
            arrangement: arrangement,
            onCopy: { [weak self] in self?.copyAndFinish() },
            onSave: { [weak self] in self?.saveAndFinish() },
            onClose: { [weak self] in self?.closeFromToolbar() }
        )
        content.frame = NSRect(origin: .zero, size: arrangement.windowFrame.size)
        content.autoresizingMask = [.width, .height]

        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: arrangement.windowFrame.size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.acceptsMouseMovedEvents = true
        window.level = CaptureWindowLevels.editor
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.contentView = content
        window.setFrame(arrangement.windowFrame, display: false)
        content.layoutSubtreeIfNeeded()

        let measured = content.toolbarFittingSize
        if abs(measured.width - estimatedToolbar.width) > 1
            || abs(measured.height - estimatedToolbar.height) > 1 {
            arrangement = Self.arrangement(
                preferredImageSize: preferredImageSize,
                originForImage: originForImage,
                visibleFrame: vis,
                toolbarSize: measured,
                center: center
            )
            content.apply(arrangement)
        }

        if !center, !arrangement.keepsCaptureAligned {
            overlay?.clearSelectionHole()
        }

        window.setFrame(arrangement.windowFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func installKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.session?.isEditingText == true {
                if event.keyCode == 53 {
                    _ = self.session?.cancelTextEditing()
                    return nil
                }
                let command = event.modifierFlags.contains(.command)
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
            let command = event.modifierFlags.contains(.command)
            if event.keyCode == 53 {
                self.dismiss()
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
    private func copyAndFinish() {
        commitPendingText()
        guard let session, session.beginExport() else { return }
        let document = session.document
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            guard let image = await self?.renderedImage(from: document) else {
                session.endExport()
                return
            }
            guard let self, !Task.isCancelled, self.session === session else {
                session.endExport()
                return
            }
            session.endExport()
            ImageExporter.copyToClipboard(image)
            self.saveTask = nil
            self.dismiss()
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
            guard let image = await self?.renderedImage(from: document) else {
                session.endExport()
                return
            }
            guard let self, !Task.isCancelled, self.session === session else {
                session.endExport()
                return
            }
            do {
                try await ImageExporter.save(image, format: format, to: url)
                guard !Task.isCancelled else {
                    session.endExport()
                    return
                }
                if copyOnComplete {
                    ImageExporter.copyToClipboard(image)
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
        guard let cgImage = await Task.detached(priority: .userInitiated, operation: {
            snapshot.renderedCGImage()
        }).value else { return nil }
        return NSImage(cgImage: cgImage, size: imageSize)
    }
}

private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
