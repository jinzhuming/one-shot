import AppKit

enum StatusItemMenu {
    static let previousRegionTag = 1001
    static let recordingTag = 1002

    @MainActor
    static func build() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = StatusItemMenuDelegate.shared
        let target = StatusItemActions.shared

        func item(_ title: String, action: Selector, hotkeyAction: HotkeyAction) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            if HotkeyCenter.shared.isRegistered(hotkeyAction),
               let hotkey = HotkeyCenter.shared.hotkey(for: hotkeyAction) {
                item.keyEquivalent = hotkey.character.lowercased()
                item.keyEquivalentModifierMask = hotkey.modifiers
            }
            return item
        }

        menu.addItem(item(String(localized: "截取区域"), action: #selector(StatusItemActions.captureArea), hotkeyAction: .captureArea))
        menu.addItem(item(String(localized: "截取窗口"), action: #selector(StatusItemActions.captureWindow), hotkeyAction: .captureWindow))
        menu.addItem(item(String(localized: "截取全屏"), action: #selector(StatusItemActions.captureFullscreen), hotkeyAction: .captureFullscreen))
        menu.addItem(item("All-in-One", action: #selector(StatusItemActions.captureAllInOne), hotkeyAction: .allInOne))

        let recording = item(
            CaptureSession.shared.isRecording
                ? String(localized: "停止录制")
                : String(localized: "录屏"),
            action: #selector(StatusItemActions.toggleRecording),
            hotkeyAction: .recording
        )
        recording.tag = recordingTag
        menu.addItem(recording)

        let previous = NSMenuItem(
            title: String(localized: "截取上次区域"),
            action: #selector(StatusItemActions.capturePrevious),
            keyEquivalent: ""
        )
        previous.tag = previousRegionTag
        previous.target = target
        previous.isEnabled = AppSettings.shared.lastSelection != nil
        menu.addItem(previous)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "设置…"), action: #selector(StatusItemActions.openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = target
        menu.addItem(settings)

        let about = NSMenuItem(title: String(localized: "关于 Shot"), action: #selector(StatusItemActions.showAbout), keyEquivalent: "")
        about.target = target
        menu.addItem(about)

        let quit = NSMenuItem(title: String(localized: "退出 Shot"), action: #selector(StatusItemActions.quit), keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
        return menu
    }

    @MainActor
    static func reload() {
        AppCoordinator.shared.reloadStatusMenu()
    }
}

@MainActor
final class StatusItemMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = StatusItemMenuDelegate()
    private var recordingTimer: Timer?
    private weak var openMenu: NSMenu?

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: StatusItemMenu.previousRegionTag)?.isEnabled = AppSettings.shared.lastSelection != nil
        if let recording = menu.item(withTag: StatusItemMenu.recordingTag) {
            recording.title = recordingTitle
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenu = menu
        menuNeedsUpdate(menu)
        recordingTimer?.invalidate()
        if CaptureSession.shared.isRecording {
            recordingTimer = Timer.scheduledTimer(
                timeInterval: 1,
                target: self,
                selector: #selector(updateRecordingMenu(_:)),
                userInfo: nil,
                repeats: true
            )
        }
        if PermissionService.shared.hasScreenRecording {
            WindowCatalog.prewarm()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        openMenu = nil
    }

    private var recordingTitle: String {
        guard CaptureSession.shared.isRecording else { return String(localized: "录屏") }
        let elapsed = Int(CaptureSession.shared.recordingElapsed ?? 0)
        let timer = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        return String(localized: "停止录制") + " " + timer
    }

    @objc private func updateRecordingMenu(_ timer: Timer) {
        guard let openMenu else {
            timer.invalidate()
            return
        }
        menuNeedsUpdate(openMenu)
    }
}

@MainActor
final class StatusItemActions: NSObject {
    static let shared = StatusItemActions()

    @objc func captureArea() { AppCoordinator.shared.startCapture(.area) }
    @objc func captureWindow() { AppCoordinator.shared.startCapture(.window) }
    @objc func captureFullscreen() { AppCoordinator.shared.startCapture(.fullscreen) }
    @objc func captureAllInOne() { AppCoordinator.shared.startCapture(.allInOne) }
    @objc func toggleRecording() { AppCoordinator.shared.toggleRecording() }
    @objc func capturePrevious() { CaptureSession.shared.capturePreviousRegion() }
    @objc func openSettings() { AppCoordinator.shared.showSettings() }
    @objc func showAbout() { AppCoordinator.shared.showAbout() }
    @objc func quit() { NSApp.terminate(nil) }
}
