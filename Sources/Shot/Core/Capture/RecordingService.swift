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
        }
    }
}

@MainActor
final class RecordingService: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var outputScreen: NSScreen?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var stopRequested = false

    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var startedAt: Date?

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
        guard stream == nil else { throw RecordingError.alreadyRecording }
        isStarting = true
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
                startContinuation = continuation
                newStream.startCapture { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in
                        self?.resumeStart(with: error)
                    }
                }
            }
            isStarting = false
            isRecording = true
            startedAt = Date()
        } catch {
            isStarting = false
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
        guard isRecording else { throw RecordingError.notRecording }

        stopRequested = true
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                finishContinuation = continuation
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
            self?.resumeStart(with: error)
            self?.resumeFinish(with: error)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.resumeFinishSuccessfully()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopRequested else { return }
            self.resumeStart(with: error)
            self.resumeFinish(with: error)
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
        guard let screen = CoordinateSpace.screen(for: window.frame) else {
            throw RecordingError.noDisplay
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = baseConfiguration(
            width: window.frame.width,
            height: window.frame.height,
            scale: screen.backingScaleFactor,
            options: options
        )
        configuration.ignoreShadowsSingleWindow = true
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

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func resumeStartSuccessfully() {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        continuation.resume()
    }

    private func resumeStart(with error: Error) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        continuation.resume(throwing: error)
    }

    private func resumeFinishSuccessfully() {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        continuation.resume()
    }

    private func resumeFinish(with error: Error) {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        continuation.resume(throwing: error)
    }

    private func cleanupAfterFailure() async {
        if let stream, let output = recordingOutput {
            try? stream.removeRecordingOutput(output)
        }
        if let stream {
            try? await stopCapture(stream)
        }
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        clearState()
    }

    private func clearState() {
        startContinuation = nil
        finishContinuation = nil
        stream = nil
        recordingOutput = nil
        outputURL = nil
        outputScreen = nil
        stopRequested = false
        isRecording = false
        startedAt = nil
        isStarting = false
    }
}
