import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import ShotKit

enum RecordingTarget {
    case region(RegionSelection)
    case window(CGWindowID)
    case display(NSScreen)
}

struct RecordingOptions: Sendable {
    var capturesAudio = false
    var captureMicrophone = false
}

struct RecordingResult {
    let url: URL
    let screen: NSScreen
    let duration: CMTime
    let fileSize: Int
}

enum RecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noDisplay
    case noWindow
    case unsupportedOutput
    case failed
    case startTimedOut
    case finishTimedOut
    case stopTimedOut

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return String(localized: "已经在录屏。")
        case .notRecording:
            return String(localized: "当前没有正在进行的录屏。")
        case .noDisplay:
            return String(localized: "找不到可用的显示器。")
        case .noWindow:
            return String(localized: "找不到要录制的窗口。")
        case .unsupportedOutput:
            return String(localized: "当前系统不支持 H.264 MP4 录屏。")
        case .failed:
            return String(localized: "录屏失败。")
        case .startTimedOut:
            return String(localized: "录屏启动超时。")
        case .finishTimedOut:
            return String(localized: "录屏文件写入超时。")
        case .stopTimedOut:
            return String(localized: "录屏停止超时。")
        }
    }
}

private final class ThrowingContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case failed
}

@MainActor
final class RecordingService: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var outputScreen: NSScreen?
    private var startGate: ThrowingContinuationGate<Void>?
    private var finishGate: ThrowingContinuationGate<Void>?
    private var startTimeoutTask: Task<Void, Never>?
    private var finishTimeoutTask: Task<Void, Never>?
    private var stopRequested = false

    private(set) var state: RecordingState = .idle
    private(set) var startedAt: Date?
    var onFailure: ((Error) -> Void)?

    var isRecording: Bool { state == .recording }
    var isStarting: Bool { state == .starting }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    func start(
        target: RecordingTarget,
        catalog: WindowCatalog,
        directory: URL,
        options: RecordingOptions = RecordingOptions()
    ) async throws {
        guard state == .idle else { throw RecordingError.alreadyRecording }
        state = .starting
        do {
            let resolved = try await resolve(target: target, catalog: catalog, options: options)
            let url = try VideoExporter.recordingURL(in: directory)
            let recordingConfiguration = SCRecordingOutputConfiguration()
            guard recordingConfiguration.availableVideoCodecTypes.contains(.h264),
                  recordingConfiguration.availableOutputFileTypes.contains(.mp4) else {
                throw RecordingError.unsupportedOutput
            }
            recordingConfiguration.outputURL = url
            recordingConfiguration.videoCodecType = .h264
            recordingConfiguration.outputFileType = .mp4

            let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
            let newStream = SCStream(
                filter: resolved.filter,
                configuration: resolved.configuration,
                delegate: self
            )

            try newStream.addRecordingOutput(output)
            stream = newStream
            recordingOutput = output
            outputURL = url
            outputScreen = resolved.screen
            stopRequested = false

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ThrowingContinuationGate(continuation)
                startGate = gate
                startTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.resumeStart(with: RecordingError.startTimedOut)
                }
                newStream.startCapture { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in
                        self?.resumeStart(with: error)
                    }
                }
            }
            state = .recording
            startedAt = Date()
        } catch {
            await cleanupAfterFailure()
            throw error
        }
    }

    func cancel() async {
        resumeStart(with: CancellationError())
        resumeFinish(with: CancellationError())
        await cleanupAfterFailure()
    }

    func stop() async throws -> RecordingResult {
        guard let stream,
              let output = recordingOutput,
              let url = outputURL,
              let screen = outputScreen else {
            throw RecordingError.notRecording
        }
        guard state == .recording else { throw RecordingError.notRecording }

        stopRequested = true
        state = .stopping
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ThrowingContinuationGate(continuation)
                finishGate = gate
                finishTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    self?.resumeFinish(with: RecordingError.finishTimedOut)
                }
                do {
                    try stream.removeRecordingOutput(output)
                } catch {
                    resumeFinish(with: error)
                }
            }
            try await stopCapture(stream)
            let result = RecordingResult(
                url: url,
                screen: screen,
                duration: output.recordedDuration,
                fileSize: output.recordedFileSize
            )
            clearState()
            return result
        } catch {
            await cleanupAfterFailure()
            throw error
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.resumeStartSuccessfully()
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            await self?.handleStreamFailure(error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.resumeFinishSuccessfully()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            await self?.handleStreamFailure(error)
        }
    }

    private struct ResolvedCapture {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let screen: NSScreen
    }

    private func resolve(
        target: RecordingTarget,
        catalog: WindowCatalog,
        options: RecordingOptions
    ) async throws -> ResolvedCapture {
        try await catalog.ensureShareableContent()

        switch target {
        case .region(let selection):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }),
                  let display = CoordinateSpace.display(matching: screen, in: catalog.displays),
                  screen.frame.contains(selection.rect) else {
                throw RecordingError.noDisplay
            }
            let filter = contentFilter(display: display, content: catalog.content)
            let scale = screen.backingScaleFactor
            let configuration = baseConfiguration(
                width: selection.rect.width,
                height: selection.rect.height,
                scale: scale,
                options: options
            )
            configuration.sourceRect = CoordinateSpace.displaySourceRect(selection.rect, on: screen)
            return ResolvedCapture(filter: filter, configuration: configuration, screen: screen)

        case .window(let id):
            guard let window = catalog.scWindow(id: id) else {
                try await catalog.refresh()
                guard let window = catalog.scWindow(id: id) else { throw RecordingError.noWindow }
                return try resolvedWindow(window, options: options)
            }
            return try resolvedWindow(window, options: options)

        case .display(let screen):
            guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
                throw RecordingError.noDisplay
            }
            let filter = contentFilter(display: display, content: catalog.content)
            let configuration = baseConfiguration(
                width: display.frame.width,
                height: display.frame.height,
                scale: screen.backingScaleFactor,
                options: options
            )
            return ResolvedCapture(filter: filter, configuration: configuration, screen: screen)
        }
    }

    private func resolvedWindow(
        _ window: SCWindow,
        options: RecordingOptions
    ) throws -> ResolvedCapture {
        // Keep recording aligned with screenshot capture: SCWindow uses the
        // top-left global window space, while NSScreen uses Cocoa coordinates.
        guard let geometry = CoordinateSpace.windowGeometry(
            fromCGWindowBounds: window.frame
        ) else {
            throw RecordingError.noDisplay
        }
        let screen = geometry.screen
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = baseConfiguration(
            width: window.frame.width,
            height: window.frame.height,
            scale: screen.backingScaleFactor,
            options: options
        )
        configuration.ignoreShadowsSingleWindow = WindowCapturePolicy.ignoresShadowsSingleWindow(
            includeShadow: false
        )
        return ResolvedCapture(filter: filter, configuration: configuration, screen: screen)
    }

    private func baseConfiguration(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        options: RecordingOptions
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = options.capturesAudio
        configuration.captureMicrophone = options.captureMicrophone
        configuration.showsCursor = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.width = RecordingLayout.evenPixelSize(points: width, scale: scale)
        configuration.height = RecordingLayout.evenPixelSize(points: height, scale: scale)
        // SCStream defaults to SDR, which is required by SCRecordingOutput.
        configuration.shouldBeOpaque = true
        return configuration
    }

    private func contentFilter(display: SCDisplay, content: SCShareableContent?) -> SCContentFilter {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let ourWindows = content?.windows.filter { $0.owningApplication?.processID == ourPID } ?? []
        if let app = content?.applications.first(where: { $0.processID == ourPID }) {
            return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        }
        return SCContentFilter(display: display, excludingWindows: ourWindows)
    }

    private func stopCapture(_ stream: SCStream, timeout: Duration = .seconds(15)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ThrowingContinuationGate(continuation)
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                gate.resume(throwing: RecordingError.stopTimedOut)
            }
            stream.stopCapture { error in
                timeoutTask.cancel()
                if let error {
                    gate.resume(throwing: error)
                } else {
                    gate.resume(returning: ())
                }
            }
        }
    }

    private func resumeStartSuccessfully() {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        let gate = startGate
        startGate = nil
        gate?.resume(returning: ())
    }

    private func resumeStart(with error: Error) {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        let gate = startGate
        startGate = nil
        gate?.resume(throwing: error)
    }

    private func resumeFinishSuccessfully() {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        let gate = finishGate
        finishGate = nil
        gate?.resume(returning: ())
    }

    private func resumeFinish(with error: Error) {
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        let gate = finishGate
        finishGate = nil
        gate?.resume(throwing: error)
    }

    private func handleStreamFailure(_ error: Error) async {
        guard state != .failed, state != .idle else { return }
        let hasWaitingOperation = startGate != nil || finishGate != nil
        state = .failed
        resumeStart(with: error)
        resumeFinish(with: error)
        guard !hasWaitingOperation else { return }

        await cleanupAfterFailure()
        onFailure?(error)
    }

    private func cleanupAfterFailure() async {
        if let stream, let output = recordingOutput {
            try? stream.removeRecordingOutput(output)
        }
        if let stream {
            try? await stopCapture(stream, timeout: .seconds(2))
        }
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        clearState()
    }

    private func clearState() {
        startTimeoutTask?.cancel()
        finishTimeoutTask?.cancel()
        startTimeoutTask = nil
        finishTimeoutTask = nil
        startGate = nil
        finishGate = nil
        stream = nil
        recordingOutput = nil
        outputURL = nil
        outputScreen = nil
        stopRequested = false
        startedAt = nil
        state = .idle
    }
}
