import Testing
@testable import ShotKit

@Test func replacingOperationsRejectsAllLateResultsAcrossOneThousandCycles() {
    var lifetime = OperationLifetime()
    for _ in 0..<1_000 {
        let old = lifetime.begin()
        let current = lifetime.begin()
        #expect(!lifetime.contains(old))
        let finishedOld = lifetime.finish(old)
        #expect(!finishedOld)
        #expect(lifetime.contains(current))
        lifetime.invalidate()
        #expect(!lifetime.contains(current))
        let finishedCancelled = lifetime.finish(current)
        #expect(!finishedCancelled)
        let completed = lifetime.begin()
        let finishedCurrent = lifetime.finish(completed)
        #expect(finishedCurrent)
        let finishedTwice = lifetime.finish(completed)
        #expect(!finishedTwice)
        #expect(!lifetime.isActive)
    }
}

@Test func systemInterruptionPolicyDoesNotRestartRecording() {
    #expect(SessionInterruptionAction.onSuspend(phase: .idle, recordingActive: false) == .none)
    #expect(SessionInterruptionAction.onSuspend(phase: .capturing, recordingActive: false) == .cancelCapture)
    #expect(SessionInterruptionAction.onSuspend(phase: .editing, recordingActive: false) == .dismissEditorChrome)
    for phase in [CapturePhase.idle, .capturing, .editing] {
        #expect(SessionInterruptionAction.onSuspend(phase: phase, recordingActive: true) == .finishRecording)
    }
}
