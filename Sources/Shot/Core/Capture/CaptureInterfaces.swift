import AppKit
import ShotKit

@MainActor
protocol ScreenCapturing {
    func captureSnapshot(catalog: WindowCatalog) async throws -> CaptureSnapshot
    func captureWindow(id: CGWindowID, catalog: WindowCatalog, includeShadow: Bool) async throws -> CaptureResult
    func captureRegionFrame(_ selection: RegionSelection, catalog: WindowCatalog) async throws -> RegionCaptureFrame
    func captureRegion(_ selection: RegionSelection, catalog: WindowCatalog) async throws -> CaptureResult
    func captureDisplay(_ screen: NSScreen, catalog: WindowCatalog) async throws -> CaptureResult
}

extension CaptureService: ScreenCapturing {}

@MainActor
protocol RecordingServicing: AnyObject {
    var state: RecordingState { get }
    var isRecording: Bool { get }
    var isStarting: Bool { get }
    var canStop: Bool { get }
    var elapsed: TimeInterval? { get }
    var recordingScreen: NSScreen? { get }
    var onFailure: ((Error) -> Void)? { get set }
    var onStateChange: ((RecordingState) -> Void)? { get set }
    func start(target: RecordingTarget, catalog: WindowCatalog, directory: URL, options: RecordingOptions, exceptingWindowIDs: [CGWindowID]) async throws -> NSScreen
    func abandon()
    func cancel() async
    func togglePause() async throws
    func stop() async throws -> RecordingResult
}

extension RecordingService: RecordingServicing {}
