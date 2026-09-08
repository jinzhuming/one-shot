public enum SessionInterruptionAction: Equatable, Sendable {
    case none
    case cancelCapture
    case finishRecording
    case dismissEditorChrome

    public static func onSuspend(phase: CapturePhase, recordingActive: Bool) -> Self {
        if recordingActive { return .finishRecording }
        switch phase {
        case .idle: return .none
        case .capturing: return .cancelCapture
        case .editing: return .dismissEditorChrome
        }
    }
}
