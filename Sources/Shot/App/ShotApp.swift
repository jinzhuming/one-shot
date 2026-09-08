import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationFinishTask: Task<Void, Never>?
    private var terminationWatchdogTask: Task<Void, Never>?
    private var didReplyToTermination = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Become accessory before SwiftUI materializes the first scene, otherwise
        // the Settings scene is presented as a blank launch window on macOS 15.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconPath = Bundle.main.path(forResource: "Shot", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }
        AppCoordinator.shared.start()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard CaptureSession.shared.hasRecordingActivity else {
            CaptureSession.shared.forceTeardownForTermination()
            return .terminateNow
        }

        // Do not let a misbehaving ScreenCaptureKit callback hold the
        // application's terminate handshake forever. The normal path gets a
        // chance to finish the MP4; the watchdog is the final escape hatch
        // and intentionally accepts losing an unfinished recording because
        // the user explicitly chose Quit.
        guard terminationFinishTask == nil else { return .terminateLater }
        didReplyToTermination = false
        terminationFinishTask = Task { @MainActor [weak self] in
            await CaptureSession.shared.finishRecordingForTermination()
            self?.replyToTermination(sender)
        }
        terminationWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            CaptureSession.shared.forceTeardownForTermination()
            self.replyToTermination(sender)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLifecycle.shared.stop()
        PinController.shared.closeAll()
        RecordingPreviewController.shared.closeAll()
        SaveLocationPresenter.dismiss()
        terminationFinishTask?.cancel()
        terminationWatchdogTask?.cancel()
        CaptureSession.shared.forceTeardownForTermination()
    }

    @MainActor
    private func replyToTermination(_ sender: NSApplication) {
        guard !didReplyToTermination else { return }
        didReplyToTermination = true
        terminationWatchdogTask?.cancel()
        terminationWatchdogTask = nil
        terminationFinishTask = nil
        sender.reply(toApplicationShouldTerminate: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        let hasUtilityWindow = sender.windows.contains { window in
            window.isVisible
                && window.styleMask.contains(.titled)
                && window.frame.width > 50
        }
        if !hasUtilityWindow {
            AppCoordinator.shared.showSettings()
        }
        return true
    }
}

@main
struct ShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusItemMenuView()
        } label: {
            StatusItemLabel()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 420)
        .defaultLaunchBehavior(.suppressed)
    }
}
