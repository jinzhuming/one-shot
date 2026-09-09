import AppKit
import ShotKit

@MainActor
final class CaptureSession: OverlayControllerDelegate {
    static let shared = CaptureSession()

    var machine = CapturePhaseMachine()
    let overlay = OverlayController()
    let captureService: any ScreenCapturing
    let recordingService: any RecordingServicing
    let recordingControls = RecordingControlBarController()
    let recordingTargetOverlay = RecordingTargetOverlayController()
    let recordingCountdown = RecordingCountdownHUD()
    let recordingClickHighlight = RecordingClickHighlightController()
    let editor = EditorPresenter()
    var captureTask: Task<Void, Never>?
    var captureWatchdogTask: Task<Void, Never>?
    var captureOperationGeneration: UInt64?
    var sessionGeneration: UInt64 = 0
    var escapeMonitors: [Any] = []
    var intent: CaptureIntent = .screenshot
    var isFinishingRecording = false
    var captureSnapshot: CaptureSnapshot?
    var scrollCaptureCoordinator: ScrollCaptureCoordinator?

    var phase: CapturePhase { machine.phase }
    var isRecording: Bool { recordingService.isRecording }
    var recordingElapsed: TimeInterval? { recordingService.elapsed }
    var hasRecordingActivity: Bool {
        recordingService.isBusy || isFinishingRecording || recordingCountdown.isVisible
    }
    var isScrollingCapture: Bool {
        intent == .scrolling && machine.phase == .capturing
    }

    /// Screenshot capture deliberately uses nonactivating panels so the app
    /// being captured keeps its native active/inactive rendering. AppKit's
    /// deactivation observer must not treat that expected state as an escape
    /// from the capture session.
    var isNonactivatingScreenshotCapture: Bool {
        machine.phase == .capturing && intent != .recording
    }

    init(captureService: (any ScreenCapturing)? = nil, recordingService: (any RecordingServicing)? = nil) {
        self.captureService = captureService ?? CaptureService()
        self.recordingService = recordingService ?? RecordingService()
        overlay.delegate = self
        self.recordingService.onFailure = { [weak self] error in
            guard let self else { return }
            self.isFinishingRecording = false
            self.fail(error)
            StatusItemMenu.reload(recordingActive: self.recordingService.isRecording)
        }
        self.recordingService.onStateChange = { [weak self] _ in
            guard let self else { return }
            self.recordingControls.update(
                state: self.recordingService.state,
                elapsed: self.recordingService.elapsed
            )
            self.recordingTargetOverlay.update(
                state: self.recordingService.state,
                elapsed: self.recordingService.elapsed
            )
            StatusItemMenu.reload(recordingActive: self.recordingService.isRecording)
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
            AppSettings.shared.lastSelection = RegionSelection(rect: rect, displayID: screen.displayID)
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
        } else if recordingService.isStarting || recordingCountdown.isVisible || isFinishingRecording {
            cancel()
        } else {
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

    func begin(_ mode: CaptureMode, intent: CaptureIntent) {
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
            overlay.present(mode: mode, confirmStyle: .start)
            return
        }
        if intent == .scrolling {
            overlay.present(
                mode: .area,
                allowsModeSwitch: false,
                hintOverride: String(localized: "拖拽选择滚动区域，松手后可调整 · Esc 取消"),
                confirmStyle: .start
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
        if recordingService.isBusy {
            invalidatePendingCapture()
            isFinishingRecording = true
            dismissRecordingChrome()
            overlay.dismiss()
            captureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.recordingService.cancel()
                self.isFinishingRecording = false
                self.removeEscapeToCancel()
                self.resetMachine()
                self.captureTask = nil
            }
            return
        }
        invalidatePendingCapture()
        scrollCaptureCoordinator = nil
        dismissRecordingChrome()
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
    }

    func overlayDidCancel() {
        cancel()
    }

    func openHistory(_ result: CaptureResult) {
        guard prepareSession() else { return }
        presentEditor(result)
    }

    func overlayDidPickWindow(id: CGWindowID) {
        overlay.showPreparationHUD()
        runCapture(timeout: recordingCaptureTimeout) { [weak self] operation in
            await self?.captureWindow(id: id, operation: operation)
        }
    }

    func overlayDidSubmitRegion(selection: RegionSelection, action: OverlayRegionAction) {
        if action == .start || (action == .default && (intent == .scrolling || intent == .recording)) {
            if intent == .scrolling {
                startScrolling(selection)
                return
            }
            overlay.showPreparationHUD()
            runCapture(timeout: recordingCaptureTimeout) { [weak self] operation in
                await self?.captureRegion(selection, operation: operation)
            }
            return
        }
        overlay.showPreparationHUD()
        runCapture { [weak self] operation in
            await self?.captureRegion(selection, operation: operation, action: action)
        }
    }

    func overlayDidPickFullscreen(screen: NSScreen) {
        overlay.showPreparationHUD()
        runCapture(timeout: recordingCaptureTimeout) { [weak self] operation in
            await self?.captureScreen(screen, operation: operation)
        }
    }

    func overlayDidInvalidateDisplayConfiguration() {
        cancel()
    }

    @discardableResult
    func prepareSession() -> Bool {
        prepareSession(for: .screenshot)
    }

    @discardableResult
    func prepareSession(for requestedIntent: CaptureIntent) -> Bool {
        if recordingService.isBusy
            || isFinishingRecording
            || recordingCountdown.isVisible {
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
        StatusItemMenu.reload(recordingActive: false)
        return true
    }

    func runCapture(
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

    func relayoutForCurrentScreens() {
        editor.relayoutForCurrentScreens()
        if hasRecordingActivity, let displayID = recordingService.recordingScreen?.displayID,
           !NSScreen.screens.contains(where: { $0.displayID == displayID }) {
            Task { @MainActor [weak self] in await self?.suspendForSystemEvent() }
        }
    }

    func suspendForSystemEvent() async {
        switch SessionInterruptionAction.onSuspend(phase: machine.phase, recordingActive: hasRecordingActivity) {
        case .none: break
        case .cancelCapture: cancel()
        case .dismissEditorChrome: editor.suspendChrome()
        case .finishRecording:
            // No UI activation or recording restart during a system transition.
            do {
                try await AsyncTimeout.run(timeout: .seconds(20), timeoutError: CaptureError.timedOut) {
                    await self.finishRecordingForTermination()
                }
            } catch {
                Diagnostics.lifecycle.error("Recording interruption exceeded its deadline")
                forceTeardownForTermination()
            }
        }
    }

    /// Tear down all UI and cancellation machinery synchronously before the
    /// process exits. Termination must not depend on ScreenCaptureKit or an
    /// exporter responding in time.
    func forceTeardownForTermination() {
        recordingService.abandon()
        isFinishingRecording = false
        invalidatePendingCapture()
        dismissRecordingChrome()
        scrollCaptureCoordinator = nil
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
    }

    func fail(_ error: Error, operation: UInt64? = nil) {
        if let operation, !isCurrent(operation) { return }
        recordingService.abandon()
        isFinishingRecording = false
        invalidatePendingCapture()
        dismissRecordingChrome()
        removeEscapeToCancel()
        overlay.dismiss()
        editor.dismiss()
        resetMachine()
        NSCursor.arrow.set()
        if !AppLifecycle.shared.isSuspended { presentError(error) }
    }

    func dismissRecordingChrome() {
        recordingControls.dismiss()
        recordingTargetOverlay.dismiss()
        recordingCountdown.hide()
        recordingClickHighlight.dismiss()
    }

    private var recordingCaptureTimeout: Duration? {
        intent == .recording ? nil : .seconds(30)
    }

    func resetMachine() {
        sessionGeneration &+= 1
        captureOperationGeneration = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        captureSnapshot = nil
        scrollCaptureCoordinator = nil
        machine.reset()
        intent = .screenshot
        WindowCatalog.shared.markSessionIdle()
        StatusItemMenu.reload(recordingActive: recordingService.isRecording)
    }

    func isCurrent(_ operation: UInt64) -> Bool {
        operation == sessionGeneration && machine.phase == .capturing
    }

    func invalidatePendingCapture() {
        sessionGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureOperationGeneration = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
    }

    func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
        alert.runModal()
    }

    func presentErrorPreservingEditor(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.window.level = NSWindow.Level(rawValue: CaptureWindowLevels.editor.rawValue + 1)
        alert.runModal()
    }

    func installEscapeToCancel() {
        removeEscapeToCancel()
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

    func removeEscapeToCancel() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors.removeAll()
    }
}
