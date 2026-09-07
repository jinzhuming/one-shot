import AppKit
import ShotKit

@MainActor
final class CaptureSession: OverlayControllerDelegate {
    static let shared = CaptureSession()

    private var machine = CapturePhaseMachine()
    private let overlay = OverlayController()
    private let captureService = CaptureService()
    private let recordingService = RecordingService()
    private let recordingControls = RecordingControlBarController()
    private let recordingTargetOverlay = RecordingTargetOverlayController()
    private let editor = EditorPresenter()
    private var captureTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var captureOperationGeneration: UInt64?
    private var sessionGeneration: UInt64 = 0
    private var escapeMonitors: [Any] = []
    private var intent: CaptureIntent = .screenshot
    private var isFinishingRecording = false
    private var captureSnapshot: CaptureSnapshot?
    private var scrollCaptureCoordinator: ScrollCaptureCoordinator?

    var phase: CapturePhase { machine.phase }
    var isRecording: Bool { recordingService.isRecording }
    var recordingElapsed: TimeInterval? { recordingService.elapsed }
    var hasRecordingActivity: Bool {
        recordingService.isRecording || recordingService.isStarting || isFinishingRecording
    }
    var isScrollingCapture: Bool {
        intent == .scrolling && machine.phase == .capturing
    }

    private init() {
        overlay.delegate = self
        recordingService.onFailure = { [weak self] error in
            guard let self else { return }
            self.recordingControls.dismiss()
            self.recordingTargetOverlay.dismiss()
            self.isFinishingRecording = false
            self.fail(error)
            StatusItemMenu.reload()
        }
        recordingService.onStateChange = { [weak self] _ in
            guard let self else { return }
            self.recordingControls.update(
                state: self.recordingService.state,
                elapsed: self.recordingService.elapsed
            )
            self.recordingTargetOverlay.update(
                state: self.recordingService.state,
                elapsed: self.recordingService.elapsed
            )
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
        runCapture { [weak self] operation in
            guard let self else { return }
            do {
                try await WindowCatalog.shared.ensureShareableContent()
                try Task.checkCancellation()
                let selection = RegionSelection(rect: rect, displayID: last.displayID)
                let result = try await self.captureService.captureRegion(selection, catalog: WindowCatalog.shared)
                try Task.checkCancellation()
                await self.handle(result, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                self.fail(error, operation: operation)
            }
        }
    }

    func begin(_ mode: CaptureMode) {
        begin(mode, intent: .screenshot)
    }

    func beginScrolling() {
        begin(.area, intent: .scrolling)
    }

    func finishScrolling() {
        guard isScrollingCapture else { return }
        scrollCaptureCoordinator?.finish()
    }

    func toggleRecording() {
        if recordingService.isRecording {
            stopRecording()
        } else if !isFinishingRecording {
            begin(.allInOne, intent: .recording)
        }
    }

    func toggleRecordingPause() {
        guard recordingService.isRecording, !isFinishingRecording else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.recordingService.togglePause()
            } catch is CancellationError {
                return
            } catch {
                // A stream failure during pause is reported by
                // RecordingService.onFailure after it has cleaned up the
                // service. Avoid presenting the same error a second time
                // when the awaiting pause operation resumes.
                guard self.recordingService.state != .idle else { return }
                self.presentError(error)
            }
        }
    }

    private func begin(_ mode: CaptureMode, intent: CaptureIntent) {
        guard prepareSession(for: intent) else { return }
        if mode == .fullscreen {
            installEscapeToCancel()
            overlay.showPreparationHUD()
            runCapture { [weak self] operation in
                await self?.captureFullscreenUnderCursor(operation: operation)
            }
            return
        }

        installEscapeToCancel()
        if intent == .recording {
            overlay.present(mode: mode)
            return
        }
        if intent == .scrolling {
            overlay.present(
                mode: .area,
                allowsModeSwitch: false,
                hintOverride: String(localized: "拖拽选择滚动区域 · Esc 取消")
            )
            return
        }
        overlay.showPreparationHUD()
        runCapture { [weak self] operation in
            await self?.prepareScreenshotOverlay(mode: mode, operation: operation)
        }
    }

    func cancel() {
        guard !isFinishingRecording else { return }
        if recordingService.isRecording || recordingService.isStarting {
            invalidatePendingCapture()
            isFinishingRecording = true
            recordingControls.dismiss()
            recordingTargetOverlay.dismiss()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.recordingService.cancel()
                self.isFinishingRecording = false
                self.removeEscapeToCancel()
                self.resetMachine()
            }
            return
        }
        invalidatePendingCapture()
        scrollCaptureCoordinator = nil
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
        runCapture { [weak self] operation in
            await self?.captureWindow(id: id, operation: operation)
        }
    }

    func overlayDidPickRegion(selection: RegionSelection) {
        if intent == .scrolling {
            startScrolling(selection)
            return
        }
        overlay.showPreparationHUD()
        runCapture { [weak self] operation in
            await self?.captureRegion(selection, operation: operation)
        }
    }

    func overlayDidPickFullscreen(screen: NSScreen) {
        overlay.showPreparationHUD()
        runCapture { [weak self] operation in
            await self?.captureScreen(screen, operation: operation)
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
        sessionGeneration &+= 1
        intent = requestedIntent
        machine.startCapture()
        StatusItemMenu.reload()
        return true
    }

    private func runCapture(
        timeout: Duration? = .seconds(30),
        _ work: @escaping (UInt64) async -> Void
    ) {
        guard machine.phase == .capturing else { return }
        captureTask?.cancel()
        captureWatchdogTask?.cancel()

        let operation = sessionGeneration
        captureOperationGeneration = operation
        if let timeout {
            captureWatchdogTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self,
                      !Task.isCancelled,
                      self.captureOperationGeneration == operation,
                      self.sessionGeneration == operation,
                      self.machine.phase == .capturing else { return }
                self.captureTask?.cancel()
                self.captureTask = nil
                self.fail(CaptureError.timedOut, operation: operation)
            }
        }

        captureTask = Task { @MainActor [weak self] in
            await work(operation)
            guard let self, self.captureOperationGeneration == operation else { return }
            self.captureOperationGeneration = nil
            self.captureWatchdogTask?.cancel()
            self.captureWatchdogTask = nil
            self.captureTask = nil
        }
    }

    private func captureWindow(id: CGWindowID, operation: UInt64) async {
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

    private func startScrolling(_ selection: RegionSelection) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) else {
            fail(CaptureError.noDisplay)
            return
        }
        let targetWindow = overlay.windowCatalog.hitTest(
            CGPoint(x: selection.rect.midX, y: selection.rect.midY)
        )
        let coordinator = ScrollCaptureCoordinator(
            captureService: captureService,
            catalog: overlay.windowCatalog,
            expectedWindow: targetWindow,
            onProgress: { [weak self] progress in
                self?.overlay.updateScrollingCapture(progress)
            }
        )
        scrollCaptureCoordinator = coordinator
        overlay.beginScrolling(on: screen) { [weak self] in
            self?.finishScrolling()
        }
        runCapture(timeout: nil) { [weak self, coordinator] operation in
            guard let self else { return }
            do {
                let result = try await coordinator.run(selection: selection)
                try Task.checkCancellation()
                guard self.isCurrent(operation) else { return }
                self.scrollCaptureCoordinator = nil
                await self.handle(result, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                self.scrollCaptureCoordinator = nil
                self.fail(error, operation: operation)
            }
        }
    }

    private func captureRegion(_ selection: RegionSelection, operation: UInt64) async {
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
            await handle(result, operation: operation)
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    private func captureFullscreenUnderCursor(operation: UInt64) async {
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

    private func captureScreen(_ screen: NSScreen, operation: UInt64) async {
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

    private func prepareScreenshotOverlay(mode: CaptureMode, operation: UInt64) async {
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

    private func startRecording(_ target: RecordingTarget, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        do {
            let screen = try await recordingService.start(
                target: target,
                catalog: overlay.windowCatalog,
                directory: AppSettings.shared.saveDirectoryURL
            )
            guard isCurrent(operation) else {
                await recordingService.cancel()
                return
            }
            recordingControls.present(
                on: screen,
                state: recordingService.state,
                elapsedProvider: { [weak self] in self?.recordingService.elapsed },
                onPause: { [weak self] in self?.toggleRecordingPause() },
                onStop: { [weak self] in self?.stopRecording() },
                onCancel: { [weak self] in self?.cancel() }
            )
            recordingTargetOverlay.present(
                target: target,
                on: screen,
                catalog: overlay.windowCatalog,
                elapsedProvider: { [weak self] in self?.recordingService.elapsed }
            )
            overlay.dismiss()
            StatusItemMenu.reload()
        } catch is CancellationError {
            return
        } catch {
            fail(error, operation: operation)
        }
    }

    private func stopRecording() {
        guard recordingService.canStop, !isFinishingRecording else { return }
        isFinishingRecording = true
        recordingControls.update(state: .stopping, elapsed: recordingService.elapsed)
        recordingTargetOverlay.dismiss()
        overlay.dismiss()
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recordingService.stop()
                self.isFinishingRecording = false
                self.recordingControls.dismiss()
                self.removeEscapeToCancel()
                self.resetMachine()
                RecordingPreviewController.shared.present(result)
                StatusItemMenu.reload()
            } catch is CancellationError {
                self.isFinishingRecording = false
                self.recordingControls.dismiss()
                self.removeEscapeToCancel()
                self.resetMachine()
                StatusItemMenu.reload()
            } catch {
                self.isFinishingRecording = false
                self.recordingControls.dismiss()
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
        recordingControls.dismiss()
        recordingTargetOverlay.dismiss()
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

    /// Tear down all UI and cancellation machinery synchronously before the
    /// process exits. Termination must not depend on ScreenCaptureKit or an
    /// exporter responding in time.
    func forceTeardownForTermination() {
        invalidatePendingCapture()
        recordingControls.dismiss()
        recordingTargetOverlay.dismiss()
        scrollCaptureCoordinator = nil
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
    }

    private func handle(_ result: CaptureResult, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        captureOperationGeneration = nil
        removeEscapeToCancel()
        let result = await applyingScreenshotBackground(to: result)
        guard !Task.isCancelled, isCurrent(operation) else { return }
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
    }

    private func presentEditor(_ result: CaptureResult) {
        machine.startEditing()
        StatusItemMenu.reload()
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

    private func applyingScreenshotBackground(to result: CaptureResult) async -> CaptureResult {
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
        guard let image = await Task.detached(priority: .userInitiated, operation: {
            snapshot.renderedCGImage()
        }).value else {
            return result
        }

        var result = result
        result.image = NSImage(cgImage: image, size: snapshot.renderedSize)
        result.hasAppliedBackground = true
        return result
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

    private func fail(_ error: Error, operation: UInt64? = nil) {
        if let operation, !isCurrent(operation) { return }
        invalidatePendingCapture()
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
        presentError(error)
    }

    private func resetMachine() {
        sessionGeneration &+= 1
        captureOperationGeneration = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        captureSnapshot = nil
        scrollCaptureCoordinator = nil
        machine.reset()
        intent = .screenshot
        WindowCatalog.shared.markSessionIdle()
        StatusItemMenu.reload()
    }

    private func isCurrent(_ operation: UInt64) -> Bool {
        operation == sessionGeneration && machine.phase == .capturing
    }

    private func invalidatePendingCapture() {
        sessionGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureOperationGeneration = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
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
            if event.keyCode == 36, self?.isScrollingCapture == true {
                self?.finishScrolling()
                return nil
            }
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }) {
            escapeMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 36, self?.isScrollingCapture == true {
                Task { @MainActor in
                    self?.finishScrolling()
                }
                return
            }
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
