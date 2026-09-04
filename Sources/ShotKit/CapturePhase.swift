public enum CapturePhase: Equatable, Sendable {
    case idle
    case capturing
    case editing
}

public struct CapturePhaseMachine: Equatable, Sendable {
    public private(set) var phase: CapturePhase = .idle

    public init() {}

    public mutating func startCapture() {
        phase = .capturing
    }

    public mutating func startEditing() {
        phase = .editing
    }

    public mutating func reset() {
        phase = .idle
    }

    public var isBusy: Bool {
        phase != .idle
    }
}
