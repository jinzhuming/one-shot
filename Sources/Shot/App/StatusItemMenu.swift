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

private enum StatusItemIcon {
    @MainActor
    static let template: NSImage = {
        let size: CGFloat = 16.5
        let drawingScale = size / 22
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.white.setStroke()

        let frame = NSRect(
            x: 2.2 * drawingScale,
            y: 2.2 * drawingScale,
            width: 17.6 * drawingScale,
            height: 17.6 * drawingScale
        )
        let arm = 4.2 * drawingScale
        let radius = 0.9 * drawingScale
        let stroke = 2.1 * drawingScale

        func strokePath(_ path: NSBezierPath) {
            path.lineWidth = stroke
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        let topLeft = NSBezierPath()
        topLeft.move(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
        topLeft.line(to: NSPoint(x: frame.minX + radius, y: frame.maxY))
        topLeft.curve(
            to: NSPoint(x: frame.minX, y: frame.maxY - radius),
            controlPoint1: NSPoint(x: frame.minX + radius * 0.45, y: frame.maxY),
            controlPoint2: NSPoint(x: frame.minX, y: frame.maxY - radius * 0.45)
        )
        topLeft.line(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
        strokePath(topLeft)

        let topRight = NSBezierPath()
        topRight.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
        topRight.line(to: NSPoint(x: frame.maxX - radius, y: frame.maxY))
        topRight.curve(
            to: NSPoint(x: frame.maxX, y: frame.maxY - radius),
            controlPoint1: NSPoint(x: frame.maxX - radius * 0.45, y: frame.maxY),
            controlPoint2: NSPoint(x: frame.maxX, y: frame.maxY - radius * 0.45)
        )
        topRight.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
        strokePath(topRight)

        let bottomLeft = NSBezierPath()
        bottomLeft.move(to: NSPoint(x: frame.minX + arm, y: frame.minY))
        bottomLeft.line(to: NSPoint(x: frame.minX + radius, y: frame.minY))
        bottomLeft.curve(
            to: NSPoint(x: frame.minX, y: frame.minY + radius),
            controlPoint1: NSPoint(x: frame.minX + radius * 0.45, y: frame.minY),
            controlPoint2: NSPoint(x: frame.minX, y: frame.minY + radius * 0.45)
        )
        bottomLeft.line(to: NSPoint(x: frame.minX, y: frame.minY + arm))
        strokePath(bottomLeft)

        let bottomRight = NSBezierPath()
        bottomRight.move(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
        bottomRight.line(to: NSPoint(x: frame.maxX - radius, y: frame.minY))
        bottomRight.curve(
            to: NSPoint(x: frame.maxX, y: frame.minY + radius),
            controlPoint1: NSPoint(x: frame.maxX - radius * 0.45, y: frame.minY),
            controlPoint2: NSPoint(x: frame.maxX, y: frame.minY + radius * 0.45)
        )
        bottomRight.line(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
        strokePath(bottomRight)

        let lensDiameter = 7.4 * drawingScale
        let lensRect = NSRect(
            x: size / 2 - lensDiameter / 2,
            y: size / 2 - lensDiameter / 2,
            width: lensDiameter,
            height: lensDiameter
        )
        let lens = NSBezierPath(ovalIn: lensRect)
        lens.lineWidth = 2.0
        lens.stroke()

        let dotDiameter = 1.8 * drawingScale
        NSBezierPath(ovalIn: NSRect(
            x: size / 2 - dotDiameter / 2,
            y: size / 2 - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )).fill()

        image.isTemplate = true
        return image
    }()
}

struct StatusItemLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: StatusItemIcon.template)
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
        if CaptureSession.shared.isScrollingCapture {
            Button(String(localized: "完成滚动截图")) {
                CaptureSession.shared.finishScrolling()
            }
            .help(String(localized: "结束采集并拼接当前内容"))
        } else {
            actionButton(String(localized: "滚动截图"), hotkey: .scrolling) {
                AppCoordinator.shared.startScrollingCapture()
            }
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
