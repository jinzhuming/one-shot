import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        guard CaptureSession.shared.hasRecordingActivity else { return .terminateNow }

        Task { @MainActor in
            await CaptureSession.shared.finishRecordingForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 420)
        .defaultLaunchBehavior(.suppressed)
    }
}
