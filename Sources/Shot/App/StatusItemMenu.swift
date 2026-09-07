import AppKit
import SwiftUI

@MainActor
final class StatusItemMenuState: ObservableObject {
    static let shared = StatusItemMenuState()

    @Published private(set) var revision = 0

    func reload() {
        revision &+= 1
    }
}

enum StatusItemMenu {
    @MainActor
    static func reload() {
        StatusItemMenuState.shared.reload()
    }
}

struct StatusItemLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "viewfinder")
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .accessibilityLabel("Shot")
            .help("Shot")
            .onAppear {
                AppCoordinator.shared.installOpenSettingsAction(openSettings)
            }
    }
}

struct StatusItemMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared
    @ObservedObject private var menuState = StatusItemMenuState.shared

    var body: some View {
        let _ = hotkeys.registrationRevision
        let _ = menuState.revision

        actionButton(String(localized: "截取区域"), hotkey: .captureArea) {
            AppCoordinator.shared.startCapture(.area)
        }
        actionButton(String(localized: "截取窗口"), hotkey: .captureWindow) {
            AppCoordinator.shared.startCapture(.window)
        }
        actionButton(String(localized: "截取全屏"), hotkey: .captureFullscreen) {
            AppCoordinator.shared.startCapture(.fullscreen)
        }
        actionButton("All-in-One", hotkey: .allInOne) {
            AppCoordinator.shared.startCapture(.allInOne)
        }
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            actionButton(recordingTitle, hotkey: .recording) {
                AppCoordinator.shared.toggleRecording()
            }
        }

        Button(String(localized: "截取上次区域")) {
            CaptureSession.shared.capturePreviousRegion()
        }
        .disabled(settings.lastSelection == nil)

        Divider()

        Button(String(localized: "设置…")) {
            AppCoordinator.shared.showSettings(using: openSettings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(String(localized: "关于 Shot")) {
            AppCoordinator.shared.showAbout()
        }

        Button(String(localized: "退出 Shot")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var recordingTitle: String {
        guard CaptureSession.shared.isRecording else { return String(localized: "录屏") }
        let elapsed = Int(CaptureSession.shared.recordingElapsed ?? 0)
        return String(localized: "停止录制") + String(format: " %02d:%02d", elapsed / 60, elapsed % 60)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        hotkey action: HotkeyAction,
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        if let shortcut = shortcut(for: action) {
            Button(title, action: perform)
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            Button(title, action: perform)
        }
    }

    private func shortcut(for action: HotkeyAction) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        guard hotkeys.isRegistered(action), let hotkey = hotkeys.hotkey(for: action) else {
            return nil
        }

        let key: KeyEquivalent
        switch hotkey.keyCode {
        case 36: key = .return
        case 48: key = .tab
        case 49: key = .space
        case 51: key = .delete
        case 53: key = .escape
        default:
            guard let character = hotkey.character.lowercased().first else { return nil }
            key = KeyEquivalent(character)
        }

        var modifiers: EventModifiers = []
        if hotkey.modifiers.contains(.control) { modifiers.insert(.control) }
        if hotkey.modifiers.contains(.option) { modifiers.insert(.option) }
        if hotkey.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if hotkey.modifiers.contains(.command) { modifiers.insert(.command) }
        return (key, modifiers)
    }
}
