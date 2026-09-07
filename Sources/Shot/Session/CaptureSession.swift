import AppKit
import ShotKit

@MainActor
final class CaptureSession: OverlayControllerDelegate {
    static let shared = CaptureSession()

    private var machine = CapturePhaseMachine()
    private let overlay = OverlayController()
    private let captureService = CaptureService()
    private let recordingService = RecordingService()
    private let editor = EditorPresenter()
    private var captureTask: Task<Void, Never>?
    private var escapeMonitors: [Any] = []
    private var intent: CaptureIntent = .screenshot
    private var isFinishingRecording = false
    private var captureSnapshot: CaptureSnapshot?

    var phase: CapturePhase { machine.phase }
    var isRecording: Bool { recordingService.isRecording }
    var recordingElapsed: TimeInterval? { recordingService.elapsed }
    var hasRecordingActivity: Bool {
        recordingService.isRecording || recordingService.isStarting || isFinishingRecording
    }

    private init() {
        overlay.delegate = self
        recordingService.onFailure = { [weak self] error in
            guard let self else { return }
            self.isFinishingRecording = false
            self.fail(error)
            StatusItemMenu.reload()
        }
        editor.onFinish = { [weak self] in
            self?.removeEscapeToCancel()
            self?.resetMachine()
        }
    }

    func capturePreviousRegion() {
        guard let last = AppSettings.shared.lastSelection else { return }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == last.displayID }) else {
            AppSettings.shared.lastSelection = nil
            return
        }
        let rect = RectMath.clampedRect(last.rect, in: screen.frame)
        guard rect.width > OverlayModeSwitch.dragThreshold,
              rect.height > OverlayModeSwitch.dragThreshold else {
            AppSettings.shared.lastSelection = nil
            return
        }
        if rect != last.rect {
            AppSettings.shared.lastSelection = LastSelection(rect: rect, displayID: screen.displayID)
        }
        guard prepareSession() else { return }
        installEscapeToCancel()
        overlay.showPreparationHUD()
        runCapture { [weak self] in
            guard let self else { return }
            do {
                try await WindowCatalog.shared.ensureShareableContent()
                try Task.checkCancellation()
                let selection = RegionSelection(rect: rect, displayID: last.displayID)
                let result = try await self.captureService.captureRegion(selection, catalog: WindowCatalog.shared)
                try Task.checkCancellation()
                await self.handle(result)
            } catch is CancellationError {
                return
            } catch {
                self.fail(error)
            }
        }
    }

    func begin(_ mode: CaptureMode) {
        begin(mode, intent: .screenshot)
    }

    func toggleRecording() {
        if recordingService.isRecording {
            stopRecording()
        } else if !isFinishingRecording {
            begin(.allInOne, intent: .recording)
        }
    }

    private func begin(_ mode: CaptureMode, intent: CaptureIntent) {
        guard prepareSession(for: intent) else { return }
        if mode == .fullscreen {
            installEscapeToCancel()
            overlay.showPreparationHUD()
            runCapture { [weak self] in
                await self?.captureFullscreenUnderCursor()
            }
            return
        }

        installEscapeToCancel()
        if intent == .recording {
            overlay.present(mode: mode)
            return
        }
        overlay.showPreparationHUD()
        runCapture { [weak self] in
            await self?.prepareScreenshotOverlay(mode: mode)
        }
    }

    func cancel() {
        if recordingService.isRecording {
            stopRecording()
            return
        }
        if recordingService.isStarting {
            captureTask?.cancel()
            Task { @MainActor [weak self] in
                await self?.recordingService.cancel()
            }
        }
        captureTask?.cancel()
        captureTask = nil
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
    }

    func overlayDidCancel() {
        cancel()
    }

    func overlayDidPickWindow(id: CGWindowID) {
        overlay.showPreparationHUD()
        runCapture { [weak self] in
            await self?.captureWindow(id: id)
        }
    }

    func overlayDidPickRegion(selection: RegionSelection) {
        overlay.showPreparationHUD()
        runCapture { [weak self] in
            await self?.captureRegion(selection)
        }
    }

    func overlayDidPickFullscreen(screen: NSScreen) {
        overlay.showPreparationHUD()
        runCapture { [weak self] in
            await self?.captureScreen(screen)
        }
    }

    func overlayDidInvalidateDisplayConfiguration() {
        cancel()
    }

    @discardableResult
    private func prepareSession() -> Bool {
        prepareSession(for: .screenshot)
    }

    @discardableResult
    private func prepareSession(for requestedIntent: CaptureIntent) -> Bool {
        if recordingService.isRecording || recordingService.isStarting {
            return false
        }
        if machine.isBusy {
            cancel()
        }
        PermissionService.shared.refresh()
        guard PermissionService.shared.hasScreenRecording else {
            AppCoordinator.shared.showOnboarding()
            return false
        }
        AppCoordinator.shared.hideUtilityWindows()
        WindowCatalog.shared.markSessionActive()
        intent = requestedIntent
        machine.startCapture()
        return true
    }

    private func runCapture(_ work: @escaping () async -> Void) {
        guard machine.phase == .capturing else { return }
        captureTask?.cancel()
        captureTask = Task { @MainActor in
            await work()
        }
    }

    private func captureWindow(id: CGWindowID) async {
        if intent == .recording {
            await startRecording(.window(id))
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
            await handle(result)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func captureRegion(_ selection: RegionSelection) async {
        if intent == .recording {
            await startRecording(.region(selection))
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
            await handle(result)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func captureFullscreenUnderCursor() async {
        do {
            try await WindowCatalog.shared.ensureShareableContent()
            try Task.checkCancellation()
            guard let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation) else {
                throw CaptureError.noDisplay
            }
            let result = try await captureService.captureDisplay(screen, catalog: WindowCatalog.shared)
            try Task.checkCancellation()
            await handle(result)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func captureScreen(_ screen: NSScreen) async {
        if intent == .recording {
            await startRecording(.display(screen))
            return
        }
        do {
            let result = try await captureService.captureDisplay(screen, catalog: overlay.windowCatalog)
            try Task.checkCancellation()
            await handle(result)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func prepareScreenshotOverlay(mode: CaptureMode) async {
        do {
            // Keep one full-resolution display image per display while the
            // overlay is interactive. Window captures are lazy and direct.
            let snapshot = try await captureService.captureSnapshot(catalog: overlay.windowCatalog)
            try Task.checkCancellation()
            guard snapshot.matchesCurrentScreens else {
                throw CaptureError.noDisplay
            }
            captureSnapshot = snapshot
            overlay.present(mode: mode, snapshot: snapshot)
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func startRecording(_ target: RecordingTarget) async {
        do {
            try await recordingService.start(
                target: target,
                catalog: overlay.windowCatalog,
                directory: AppSettings.shared.saveDirectoryURL
            )
            overlay.dismiss()
            StatusItemMenu.reload()
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    private func stopRecording() {
        guard recordingService.isRecording, !isFinishingRecording else { return }
        isFinishingRecording = true
        overlay.dismiss()
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recordingService.stop()
                self.isFinishingRecording = false
                self.removeEscapeToCancel()
                self.resetMachine()
                RecordingPreviewController.shared.present(result)
                StatusItemMenu.reload()
            } catch is CancellationError {
                self.isFinishingRecording = false
                self.removeEscapeToCancel()
                self.resetMachine()
                StatusItemMenu.reload()
            } catch {
                self.isFinishingRecording = false
                self.fail(error)
            }
        }
    }

    func finishRecordingForTermination() async {
        if isFinishingRecording {
            await captureTask?.value
            return
        }
        guard recordingService.isRecording || recordingService.isStarting else { return }

        isFinishingRecording = true
        overlay.dismiss()
        captureTask?.cancel()
        if recordingService.isStarting {
            await recordingService.cancel()
        } else {
            _ = try? await recordingService.stop()
        }
        isFinishingRecording = false
        removeEscapeToCancel()
        captureTask = nil
        resetMachine()
    }

    private func handle(_ result: CaptureResult) async {
        removeEscapeToCancel()
        switch AppSettings.shared.afterCaptureAction {
        case .annotate:
            presentEditor(result)
        case .copy:
            if ImageExporter.copyToClipboard(result.image) {
                overlay.dismiss()
                resetMachine()
                SaveLocationPresenter.showCopied(on: result.screen)
            } else {
                presentEditor(result)
                presentErrorPreservingEditor(ImageExporter.ExportError.clipboardFailed)
            }
        case .save:
            overlay.suspendForModal()
            switch await finishSave(result.image) {
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
    }

    private func presentEditor(_ result: CaptureResult) {
        machine.startEditing()
        switch AppSettings.shared.annotationWindowPlacement {
        case .inPlace:
            editor.presentInPlace(result: result, overlay: overlay)
        case .centered:
            editor.presentCentered(result: result, overlay: overlay)
        }
    }

    private enum SaveOutcome {
        case saved(URL)
        case cancelled
        case failed(Error)
    }

    private func finishSave(_ image: NSImage) async -> SaveOutcome {
        let settings = AppSettings.shared
        guard let url = ImageExporter.destinationURL(settings: settings) else {
            return .cancelled
        }
        do {
            try await ImageExporter.save(image, format: settings.saveFormat, to: url)
            if settings.copyOnComplete,
               !ImageExporter.copyToClipboard(image) {
                return .failed(ImageExporter.ExportError.clipboardFailed)
            }
            return .saved(url)
        } catch {
            return .failed(error)
        }
    }

    private func fail(_ error: Error) {
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
        presentError(error)
    }

    private func resetMachine() {
        captureSnapshot = nil
        machine.reset()
        intent = .screenshot
        WindowCatalog.shared.markSessionIdle()
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
        alert.runModal()
    }

    private func presentErrorPreservingEditor(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
        alert.runModal()
    }

    private func installEscapeToCancel() {
        removeEscapeToCancel()
        NSApp.activate(ignoringOtherApps: true)
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }) {
            escapeMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.cancel()
            }
        }) {
            escapeMonitors.append(global)
        }
    }

    private func removeEscapeToCancel() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors.removeAll()
    }
}
