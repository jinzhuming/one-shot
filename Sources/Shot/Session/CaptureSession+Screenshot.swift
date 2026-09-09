import AppKit
import ShotKit

@MainActor
extension CaptureSession {
    func captureWindow(id: CGWindowID, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        if intent == .recording {
            await startRecording(.window(id), operation: operation)
            return
        }
        do {
            let includeShadow = AppSettings.shared.includeWindowShadow
            // A display snapshot cannot preserve a window shadow at the
            // window boundary. Capture the selected window lazily so the
            // interactive session never needs two full-display variants.
            captureSnapshot = nil
            let result = try await captureService.captureWindow(
                id: id,
                catalog: overlay.windowCatalog,
                includeShadow: includeShadow
            )
            try Task.checkCancellation()
            await handle(result, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    func captureRegion(
        _ selection: RegionSelection,
        operation: UInt64,
        action: OverlayRegionAction = .default
    ) async {
        guard isCurrent(operation) else { return }
        if intent == .recording {
            await startRecording(.region(selection), operation: operation)
            return
        }
        do {
            let result: CaptureResult
            let snapshot = captureSnapshot
            captureSnapshot = nil
            if let snapshot {
                result = try snapshot.cropRegion(selection)
            } else {
                result = try await captureService.captureRegion(selection, catalog: overlay.windowCatalog)
            }
            try Task.checkCancellation()
            await handle(result, operation: operation, action: action)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    func captureFullscreenUnderCursor(operation: UInt64) async {
        guard isCurrent(operation) else { return }
        do {
            try await WindowCatalog.shared.ensureShareableContent()
            try Task.checkCancellation()
            guard let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation) else {
                throw CaptureError.noDisplay
            }
            let result = try await captureService.captureDisplay(screen, catalog: WindowCatalog.shared)
            try Task.checkCancellation()
            await handle(result, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    func captureScreen(_ screen: NSScreen, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        if intent == .recording {
            await startRecording(.display(screen), operation: operation)
            return
        }
        do {
            let result = try await captureService.captureDisplay(screen, catalog: overlay.windowCatalog)
            try Task.checkCancellation()
            await handle(result, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    func prepareScreenshotOverlay(mode: CaptureMode, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        do {
            // Keep one full-resolution display image per display while the
            // overlay is interactive. Window captures are lazy and direct.
            let snapshot = try await captureService.captureSnapshot(catalog: overlay.windowCatalog)
            try Task.checkCancellation()
            guard snapshot.matchesCurrentScreens else {
                throw CaptureError.noDisplay
            }
            guard isCurrent(operation) else { return }
            captureSnapshot = snapshot
            overlay.present(mode: mode, snapshot: snapshot)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    func handle(
        _ result: CaptureResult,
        operation: UInt64,
        action: OverlayRegionAction = .default
    ) async {
        guard isCurrent(operation) else { return }
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        captureOperationGeneration = nil
        removeEscapeToCancel()
        let result = await applyingScreenshotBackground(to: result)
        guard !Task.isCancelled, isCurrent(operation) else { return }
        switch resolvedAction(action) {
        case .copy:
            finishCopy(result)
        case .save:
            await finishSaveFlow(result, operation: operation)
        case .pin:
            overlay.dismiss()
            resetMachine()
            PinController.shared.present(result.image, on: result.screen) { [weak self] in
                self?.restorePinnedCapture(result)
            }
        case .ocr:
            overlay.showPreparationHUD()
            installEscapeToCancel()
            do {
                let text = try await OCRService.recognizeText(in: result.image)
                guard !Task.isCancelled, isCurrent(operation) else { return }
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.setString(text, forType: .string) else {
                        throw ImageExporter.ExportError.clipboardFailed
                    }
                }
                overlay.dismiss()
                removeEscapeToCancel()
                resetMachine()
                ScreenshotHistoryStore.add(result.image)
                SaveLocationPresenter.showCopied(
                    message: text.isEmpty ? String(localized: "未识别到文字") : String(localized: "已复制识别文字"),
                    on: result.screen
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(operation) else { return }
                overlay.hidePreparationHUD()
                presentEditor(result)
                presentErrorPreservingEditor(error)
            }
        case .annotate, .default, .start:
            presentEditor(result)
        }
    }

    func resolvedAction(_ action: OverlayRegionAction) -> OverlayRegionAction {
        action == .default ? .annotate : action
    }

    func finishCopy(_ result: CaptureResult) {
        if ImageExporter.copyToClipboard(result.image) {
            overlay.dismiss()
            resetMachine()
            ScreenshotHistoryStore.add(result.image)
            SaveLocationPresenter.showCopied(on: result.screen)
        } else {
            presentEditor(result)
            presentErrorPreservingEditor(ImageExporter.ExportError.clipboardFailed)
        }
    }

    func finishSaveFlow(_ result: CaptureResult, operation: UInt64) async {
        overlay.suspendForModal()
        switch await finishSave(result.image, operation: operation) {
        case .saved where !isCurrent(operation):
            return
        case .cancelled where !isCurrent(operation):
            return
        case .failed where !isCurrent(operation):
            return
        case .saved(let url):
            overlay.dismiss()
            resetMachine()
            SaveLocationPresenter.showSaved(at: url, on: result.screen)
        case .cancelled:
            overlay.dismiss()
            resetMachine()
        case .failed(let error):
            overlay.resumeAfterModal()
            presentEditor(result)
            presentErrorPreservingEditor(error)
        }
    }

    func presentEditor(_ result: CaptureResult) {
        machine.startEditing()
        WindowCatalog.shared.markSessionIdle()
        StatusItemMenu.reload(recordingActive: false)
        if result.kind == .scrolling || result.hasAppliedBackground {
            editor.presentCentered(result: result, overlay: overlay)
            return
        }
        switch AppSettings.shared.annotationWindowPlacement {
        case .inPlace:
            editor.presentInPlace(result: result, overlay: overlay)
        case .centered:
            editor.presentCentered(result: result, overlay: overlay)
        }
    }

    func restorePinnedCapture(_ result: CaptureResult) {
        guard prepareSession() else { return }
        machine.startEditing()
        WindowCatalog.shared.markSessionIdle()
        StatusItemMenu.reload(recordingActive: false)
        editor.presentCentered(result: result, overlay: overlay)
    }

    func restoreEditorSession(_ session: EditSession, on screen: NSScreen) {
        guard prepareSession() else { return }
        machine.startEditing()
        WindowCatalog.shared.markSessionIdle()
        editor.restoreAnnotation(session, on: screen)
        StatusItemMenu.reload(recordingActive: false)
    }

    func applyingScreenshotBackground(to result: CaptureResult) async -> CaptureResult {
        guard result.kind == .window,
              let backgroundURL = AppSettings.shared.screenshotBackgroundURL(for: result.screen) else {
            return result
        }

        guard let snapshot = ScreenshotBackgroundRenderSnapshot(
            screenshot: result.image,
            backgroundURL: backgroundURL
        ) else {
            return result
        }
        guard let image = try? await BackgroundWork.run({ snapshot.renderedCGImage() }) else {
            return result
        }

        var result = result
        result.image = NSImage(cgImage: image, size: snapshot.renderedSize)
        result.hasAppliedBackground = true
        return result
    }

    enum SaveOutcome {
        case saved(URL)
        case cancelled
        case failed(Error)
    }

    func finishSave(_ image: NSImage, operation: UInt64) async -> SaveOutcome {
        let settings = AppSettings.shared
        guard let destination = ImageExporter.destination(settings: settings) else {
            return .cancelled
        }
        let format = settings.saveFormat
        let copyOnComplete = settings.copyOnComplete
        do {
            let url = try await ImageExporter.save(image, format: format, destination: destination)
            guard !Task.isCancelled, isCurrent(operation) else { return .cancelled }
            // A completed file belongs in history even when the optional
            // copy-on-complete step fails.
            ScreenshotHistoryStore.add(image)
            if copyOnComplete,
               !ImageExporter.copyToClipboard(image) {
                return .failed(ImageExporter.ExportError.savedButClipboardFailed)
            }
            return .saved(url)
        } catch {
            return .failed(error)
        }
    }

}
