import AppKit
import ShotKit

@MainActor
extension CaptureSession {
    func startRecording(_ target: RecordingTarget, operation: UInt64) async {
        guard isCurrent(operation) else { return }
        overlay.dismiss()
        do {
            let screen = try recordingScreen(for: target)
            try await waitForRecordingCountdown(on: screen, operation: operation)
            try Task.checkCancellation()
            guard isCurrent(operation) else { return }

            var captureMicrophone = false
            var microphoneDenied = false
            if AppSettings.shared.captureMicrophone {
                PermissionService.shared.refresh()
                if PermissionService.shared.hasMicrophone {
                    captureMicrophone = true
                } else {
                    let granted = await PermissionService.shared.requestMicrophone()
                    try Task.checkCancellation()
                    guard isCurrent(operation) else { return }
                    captureMicrophone = granted
                    microphoneDenied = !granted
                }
            }
            let options = RecordingOptions(
                capturesAudio: AppSettings.shared.captureSystemAudio,
                captureMicrophone: captureMicrophone
            )

            var exceptingWindowIDs: [CGWindowID] = []
            if AppSettings.shared.highlightClicks {
                recordingClickHighlight.present(in: recordingHighlightFrame(for: target, on: screen))
                try await overlay.windowCatalog.refresh()
                try Task.checkCancellation()
                guard isCurrent(operation) else {
                    recordingClickHighlight.dismiss()
                    return
                }
                if let windowID = recordingClickHighlight.windowID {
                    exceptingWindowIDs = [windowID]
                }
            }

            let recordedScreen = try await recordingService.start(
                target: target,
                catalog: overlay.windowCatalog,
                directory: AppSettings.shared.saveDirectoryURL,
                options: options,
                exceptingWindowIDs: exceptingWindowIDs
            )
            guard isCurrent(operation) else {
                recordingClickHighlight.dismiss()
                await recordingService.cancel()
                return
            }
            if microphoneDenied {
                SaveLocationPresenter.showCopied(
                    message: String(localized: "未授权麦克风，已继续录屏且不收录人声。可在系统设置中开启。"),
                    on: recordedScreen
                )
            }
            recordingControls.present(
                on: recordedScreen,
                state: recordingService.state,
                elapsedProvider: { [weak self] in self?.recordingService.elapsed },
                onPause: { [weak self] in self?.toggleRecordingPause() },
                onStop: { [weak self] in self?.stopRecording() },
                onCancel: { [weak self] in self?.cancel() }
            )
            recordingTargetOverlay.present(
                target: target,
                on: recordedScreen,
                catalog: overlay.windowCatalog,
                elapsedProvider: { [weak self] in self?.recordingService.elapsed }
            )
            StatusItemMenu.reload()
        } catch is CancellationError {
            recordingCountdown.hide()
            recordingClickHighlight.dismiss()
            return
        } catch {
            recordingCountdown.hide()
            recordingClickHighlight.dismiss()
            fail(error, operation: operation)
        }
    }

    func waitForRecordingCountdown(on screen: NSScreen, operation: UInt64) async throws {
        let seconds = AppSettings.shared.recordingCountdown.rawValue
        guard seconds > 0 else { return }
        recordingCountdown.show(seconds: seconds, on: screen)
        defer { recordingCountdown.hide() }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try Task.checkCancellation()
            guard isCurrent(operation) else { throw CancellationError() }
            recordingCountdown.update(remaining)
            try await Task.sleep(for: .seconds(1))
        }
    }

    func recordingScreen(for target: RecordingTarget) throws -> NSScreen {
        switch target {
        case .region(let selection):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) else {
                throw RecordingError.noDisplay
            }
            return screen
        case .window(let id):
            if let window = overlay.windowCatalog.windows.first(where: { $0.windowID == id }) {
                if let screen = CoordinateSpace.screen(for: window.frame) {
                    return screen
                }
            }
            throw RecordingError.noDisplay
        case .display(let screen):
            return screen
        }
    }

    func recordingHighlightFrame(for target: RecordingTarget, on screen: NSScreen) -> CGRect {
        switch target {
        case .region(let selection):
            return selection.rect
        case .window(let id):
            return overlay.windowCatalog.windows.first(where: { $0.windowID == id })?.frame ?? screen.frame
        case .display:
            return screen.frame
        }
    }

    func stopRecording() {
        guard recordingService.canStop, !isFinishingRecording else { return }
        isFinishingRecording = true
        recordingControls.update(state: .stopping, elapsed: recordingService.elapsed)
        recordingTargetOverlay.dismiss()
        recordingClickHighlight.dismiss()
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
                if !AppLifecycle.shared.isSuspended { RecordingPreviewController.shared.present(result) }
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
        recordingCountdown.hide()
        recordingClickHighlight.dismiss()
        overlay.dismiss()
        captureTask?.cancel()
        if recordingService.isStarting {
            await recordingService.cancel()
        } else {
            while !recordingService.canStop, recordingService.isRecording, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if recordingService.canStop {
                do { _ = try await recordingService.stop() }
                catch { Diagnostics.lifecycle.error("Recording could not finish during interruption") }
            } else {
                await recordingService.cancel()
            }
        }
        isFinishingRecording = false
        removeEscapeToCancel()
        captureTask = nil
        resetMachine()
    }

}
