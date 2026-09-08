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
    case pausing
    case paused
    case resuming
    case stopping
    case failed
}

private struct RecordingSegment {
    let url: URL
    let duration: CMTime
    let fileSize: Int
}

private final class RecordingOutputStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait(timeout: Duration) async throws {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resume(throwing: RecordingError.startTimedOut)
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resume(returning value: Void) {
        resume(with: .success(value))
    }

    func resume(throwing error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor
final class RecordingService: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var generation: UInt64 = 0
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var outputDirectory: URL?
    private var outputScreen: NSScreen?
    private var segments: [RecordingSegment] = []
    private var finishGate: ThrowingContinuationGate<Void>?
    private var finishTimeoutTask: Task<Void, Never>?
    private var outputStartGates: [ObjectIdentifier: RecordingOutputStartGate] = [:]
    private var startFailure: Error?
    private var stopRequested = false
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0

    private(set) var state: RecordingState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    private(set) var startedAt: Date?
    var onFailure: ((Error) -> Void)?
    var onStateChange: ((RecordingState) -> Void)?

    var isRecording: Bool { state == .recording || state == .pausing || state == .paused || state == .resuming }
    var isStarting: Bool { state == .starting }
    var isPaused: Bool { state == .paused }
    var canStop: Bool { state == .recording || state == .paused }
    var recordingScreen: NSScreen? { outputScreen }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        let end = pausedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt) - accumulatedPauseDuration)
    }

    @discardableResult
    func start(
        target: RecordingTarget,
        catalog: WindowCatalog,
        directory: URL,
        options: RecordingOptions = RecordingOptions(),
        exceptingWindowIDs: [CGWindowID] = []
    ) async throws -> NSScreen {
        guard state == .idle else { throw RecordingError.alreadyRecording }
        generation &+= 1
        let operation = generation
        state = .starting
        do {
            let resolved = try await resolve(
                target: target,
                catalog: catalog,
                options: options,
                exceptingWindowIDs: exceptingWindowIDs
            )
            try validate(operation)
            let (output, url) = try makeRecordingOutput()
            let newStream = SCStream(
                filter: resolved.filter,
                configuration: resolved.configuration,
                delegate: self
            )

            let outputStartGate = registerOutputStartGate(for: output)
            stream = newStream
            recordingOutput = output
            outputURL = url
            outputDirectory = directory
            outputScreen = resolved.screen
            segments.removeAll(keepingCapacity: true)
            stopRequested = false
            startFailure = nil
            pausedAt = nil
            accumulatedPauseDuration = 0
            try newStream.addRecordingOutput(output)

            try await startCapture(newStream)
            try validate(operation)
            if let startFailure {
                throw startFailure
            }
            defer { outputStartGates.removeValue(forKey: ObjectIdentifier(output)) }
            try await outputStartGate.wait(timeout: .seconds(15))
            guard state == .starting, self.stream === newStream else {
                throw CancellationError()
            }
            state = .recording
            startedAt = Date()
            return resolved.screen
        } catch {
            if generation == operation { await cleanupAfterFailure() }
            throw error
        }
    }

    func cancel() async {
        stopRequested = true
        outputStartGates.values.forEach { $0.resume(throwing: CancellationError()) }
        resumeFinish(with: CancellationError())
        await cleanupAfterFailure()
    }

    func togglePause() async throws {
        switch state {
        case .recording:
            try await pause()
        case .paused:
            try await resume()
        default:
            return
        }
    }

    func stop() async throws -> RecordingResult {
        guard let stream,
              let directory = outputDirectory,
              let screen = outputScreen else {
            throw RecordingError.notRecording
        }
        guard canStop else {
            throw RecordingError.notRecording
        }

        let operation = generation
        stopRequested = true
        state = .stopping
        do {
            if let output = recordingOutput {
                let segment = try await finishCurrentOutput(output, from: stream)
                try validate(operation)
                segments.append(segment)
            }
            try await stopCapture(stream)
            try validate(operation)

            let sourceURLs = segments.map(\.url)
            let mergedURL = try await VideoExporter.mergeRecordingSegments(sourceURLs)
            try validate(operation)
            let finalURL: URL
            do {
                finalURL = try await VideoExporter.finalizeRecording(
                    sourceURL: mergedURL,
                    in: directory
                )
            } catch {
                // Keep the completed temporary recording available to the
                // preview when the configured folder is not accessible yet.
                // The preview's Save action can then ask the user for a
                // different location without losing the recording.
                finalURL = mergedURL
            }
            try validate(operation)
            for sourceURL in sourceURLs where sourceURL != finalURL {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            let result = RecordingResult(
                url: finalURL,
                screen: screen,
                duration: segments.reduce(.zero) { CMTimeAdd($0, $1.duration) },
                fileSize: segments.reduce(0) { $0 + $1.fileSize }
            )
            clearState()
            return result
        } catch {
            if generation == operation { await cleanupAfterFailure() }
            throw error
        }
    }

    private func pause() async throws {
        guard state == .recording,
              let stream,
              let output = recordingOutput else { throw RecordingError.notRecording }
        let operation = generation
        state = .pausing
        do {
            let segment = try await finishCurrentOutput(output, from: stream)
            try validate(operation)
            segments.append(segment)
            recordingOutput = nil
            outputURL = nil
            pausedAt = Date()
            state = .paused
        } catch {
            if generation == operation, state == .pausing {
                state = .recording
            }
            throw error
        }
    }

    private func resume() async throws {
        guard state == .paused, let stream else { throw RecordingError.notRecording }
        let operation = generation
        state = .resuming
        do {
            let (output, url) = try makeRecordingOutput()
            let outputStartGate = registerOutputStartGate(for: output)
            recordingOutput = output
            outputURL = url
            try stream.addRecordingOutput(output)
            defer { outputStartGates.removeValue(forKey: ObjectIdentifier(output)) }
            try await outputStartGate.wait(timeout: .seconds(15))
            try validate(operation)
            guard state == .resuming, self.stream === stream else {
                throw CancellationError()
            }
            if let pausedAt {
                accumulatedPauseDuration += Date().timeIntervalSince(pausedAt)
            }
            self.pausedAt = nil
            state = .recording
        } catch {
            guard generation == operation else { throw CancellationError() }
            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
                self.outputURL = nil
                self.recordingOutput = nil
            }
            if state == .resuming {
                state = .paused
            }
            throw error
        }
    }

    private func makeRecordingOutput() throws -> (SCRecordingOutput, URL) {
        let url = try VideoExporter.temporaryRecordingURL()
        let recordingConfiguration = SCRecordingOutputConfiguration()
        guard recordingConfiguration.availableVideoCodecTypes.contains(.h264),
              recordingConfiguration.availableOutputFileTypes.contains(.mp4) else {
            throw RecordingError.unsupportedOutput
        }
        recordingConfiguration.outputURL = url
        recordingConfiguration.videoCodecType = .h264
        recordingConfiguration.outputFileType = .mp4
        return (
            SCRecordingOutput(configuration: recordingConfiguration, delegate: self),
            url
        )
    }

    private func registerOutputStartGate(for output: SCRecordingOutput) -> RecordingOutputStartGate {
        let gate = RecordingOutputStartGate()
        outputStartGates[ObjectIdentifier(output)] = gate
        return gate
    }

    private func finishCurrentOutput(
        _ output: SCRecordingOutput,
        from stream: SCStream
    ) async throws -> RecordingSegment {
        guard let url = outputURL else { throw RecordingError.notRecording }
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
        return RecordingSegment(
            url: url,
            duration: output.recordedDuration,
            fileSize: output.recordedFileSize
        )
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentOutput = self.recordingOutput,
                  currentOutput === recordingOutput else { return }
            self.outputStartGates[ObjectIdentifier(recordingOutput)]?.resume(throwing: error)
            await self.handleStreamFailure(error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentOutput = self.recordingOutput,
                  currentOutput === recordingOutput else { return }
            if self.finishGate != nil {
                self.resumeFinishSuccessfully()
            } else if self.state == .starting || self.state == .resuming {
                self.outputStartGates[ObjectIdentifier(recordingOutput)]?.resume(throwing: RecordingError.failed)
                await self.handleStreamFailure(RecordingError.failed)
            } else if self.state == .recording {
                await self.handleStreamFailure(RecordingError.failed)
            }
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentOutput = self.recordingOutput,
                  currentOutput === recordingOutput else { return }
            self.outputStartGates[ObjectIdentifier(recordingOutput)]?.resume(returning: ())
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentStream = self.stream,
                  currentStream === stream else { return }
            await self.handleStreamFailure(error)
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
        options: RecordingOptions,
        exceptingWindowIDs: [CGWindowID]
    ) async throws -> ResolvedCapture {
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: RecordingError.startTimedOut
        ) {
            try await catalog.ensureShareableContent()
        }

        switch target {
        case .region(let selection):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }),
                  let display = CoordinateSpace.display(matching: screen, in: catalog.displays),
                  screen.frame.contains(selection.rect) else {
                throw RecordingError.noDisplay
            }
            let filter = contentFilter(
                display: display,
                content: catalog.content,
                exceptingWindowIDs: exceptingWindowIDs
            )
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
                try await AsyncTimeout.run(
                    timeout: .seconds(15),
                    timeoutError: RecordingError.startTimedOut
                ) {
                    try await catalog.refresh()
                }
                guard let window = catalog.scWindow(id: id) else { throw RecordingError.noWindow }
                return try resolvedWindow(
                    window,
                    catalog: catalog,
                    options: options,
                    overlayWindowIDs: exceptingWindowIDs
                )
            }
            return try resolvedWindow(
                window,
                catalog: catalog,
                options: options,
                overlayWindowIDs: exceptingWindowIDs
            )

        case .display(let screen):
            guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
                throw RecordingError.noDisplay
            }
            let filter = contentFilter(
                display: display,
                content: catalog.content,
                exceptingWindowIDs: exceptingWindowIDs
            )
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
        catalog: WindowCatalog,
        options: RecordingOptions,
        overlayWindowIDs: [CGWindowID]
    ) throws -> ResolvedCapture {
        // Keep recording aligned with screenshot capture: SCWindow uses the
        // top-left global window space, while NSScreen uses Cocoa coordinates.
        guard let geometry = CoordinateSpace.windowGeometry(
            fromCGWindowBounds: window.frame
        ) else {
            throw RecordingError.noDisplay
        }
        let screen = geometry.screen
        if WindowCapturePolicy.recordsWindowAsDisplayCrop(includedOverlayCount: overlayWindowIDs.count),
           let display = CoordinateSpace.display(matching: screen, in: catalog.displays) {
            return resolvedWindowWithOverlays(
                window,
                geometry: geometry,
                display: display,
                catalog: catalog,
                options: options,
                overlayWindowIDs: overlayWindowIDs
            )
        }
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

    private func resolvedWindowWithOverlays(
        _ window: SCWindow,
        geometry: (frame: CGRect, screen: NSScreen),
        display: SCDisplay,
        catalog: WindowCatalog,
        options: RecordingOptions,
        overlayWindowIDs: [CGWindowID]
    ) -> ResolvedCapture {
        let overlayWindows = overlayWindowIDs.compactMap { catalog.scWindow(id: $0) }
        let filter: SCContentFilter
        if overlayWindows.isEmpty {
            filter = contentFilter(
                display: display,
                content: catalog.content,
                exceptingWindowIDs: overlayWindowIDs
            )
        } else {
            filter = contentFilter(display: display, includingWindows: [window] + overlayWindows)
        }
        let configuration = baseConfiguration(
            width: geometry.frame.width,
            height: geometry.frame.height,
            scale: geometry.screen.backingScaleFactor,
            options: options
        )
        let contentRect = filter.contentRect
        if overlayWindows.isEmpty
            || contentRect.width > geometry.frame.width + 1
            || contentRect.height > geometry.frame.height + 1 {
            configuration.sourceRect = CoordinateSpace.displaySourceRect(
                geometry.frame,
                on: geometry.screen
            )
        }
        return ResolvedCapture(filter: filter, configuration: configuration, screen: geometry.screen)
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

    private func contentFilter(
        display: SCDisplay,
        content: SCShareableContent?,
        exceptingWindowIDs: [CGWindowID]
    ) -> SCContentFilter {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let excepting = content?.windows.filter { exceptingWindowIDs.contains($0.windowID) } ?? []
        if let app = content?.applications.first(where: { $0.processID == ourPID }) {
            return SCContentFilter(
                display: display,
                excludingApplications: [app],
                exceptingWindows: excepting
            )
        }
        let ourWindows = content?.windows.filter { window in
            window.owningApplication?.processID == ourPID && !exceptingWindowIDs.contains(window.windowID)
        } ?? []
        return SCContentFilter(display: display, excludingWindows: ourWindows)
    }

    /// Swift imports both the window and application `including:` filters under
    /// the same selector; pin the window overload through its function type.
    private func contentFilter(display: SCDisplay, includingWindows windows: [SCWindow]) -> SCContentFilter {
        let makeFilter: (SCDisplay, [SCWindow]) -> SCContentFilter = SCContentFilter.init(display:including:)
        return makeFilter(display, windows)
    }

    private func startCapture(_ stream: SCStream, timeout: Duration = .seconds(15)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ThrowingContinuationGate(continuation)
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                gate.resume(throwing: RecordingError.startTimedOut)
            }
            stream.startCapture { error in
                timeoutTask.cancel()
                if let error {
                    gate.resume(throwing: error)
                } else {
                    gate.resume(returning: ())
                }
            }
        }
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
        if stopRequested {
            resumeFinish(with: error)
            return
        }
        if state == .starting || state == .resuming {
            startFailure = error
            if let recordingOutput {
                outputStartGates[ObjectIdentifier(recordingOutput)]?.resume(throwing: error)
            }
            return
        }
        state = .failed
        resumeFinish(with: error)
        let failedGeneration = generation
        await cleanupAfterFailure()
        if generation == failedGeneration &+ 1, state == .idle { onFailure?(error) }
    }

    func abandon() {
        let resources = detachResources()
        Task { await discard(resources) }
    }

    private struct RetiredRecording {
        let stream: SCStream?
        let output: SCRecordingOutput?
        let urls: [URL]
    }

    private func detachResources() -> RetiredRecording {
        let resources = RetiredRecording(stream: stream, output: recordingOutput,
                                         urls: segments.map(\.url) + [outputURL].compactMap { $0 })
        clearState()
        return resources
    }

    private func cleanupAfterFailure() async { await discard(detachResources()) }

    private func discard(_ resources: RetiredRecording) async {
        if let stream = resources.stream, let output = resources.output { try? stream.removeRecordingOutput(output) }
        if let stream = resources.stream { try? await stopCapture(stream, timeout: .seconds(2)) }
        // Cleanup must outlive cancellation of the operation it is retiring.
        await Task.detached(priority: .utility) {
            for url in resources.urls { try? FileManager.default.removeItem(at: url) }
        }.value
    }

    private func validate(_ operation: UInt64) throws {
        try Task.checkCancellation()
        guard operation == generation else { throw CancellationError() }
    }

    private func clearState() {
        generation &+= 1
        outputStartGates.values.forEach { $0.resume(throwing: CancellationError()) }
        resumeFinish(with: CancellationError())
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        finishGate = nil
        startFailure = nil
        outputStartGates.removeAll()
        stream = nil
        recordingOutput = nil
        outputURL = nil
        outputDirectory = nil
        outputScreen = nil
        segments.removeAll()
        stopRequested = false
        pausedAt = nil
        accumulatedPauseDuration = 0
        startedAt = nil
        state = .idle
    }
}
