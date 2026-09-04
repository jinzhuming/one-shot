import AppKit
import CoreGraphics
import Foundation

@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var hasScreenRecording: Bool
    @Published private(set) var screenRecordingNeedsRestart: Bool

    private var pollTimer: Timer?

    private init() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        screenRecordingNeedsRestart = false
    }

    func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        hasScreenRecording = granted
        if granted {
            screenRecordingNeedsRestart = false
        }
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        if granted, !hasScreenRecording {
            screenRecordingNeedsRestart = true
        }
        return granted
    }

    func quitForPermissionRestart() {
        NSApp.terminate(nil)
    }

    func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        pollTimer?.tolerance = 0.5
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
