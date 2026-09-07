import SwiftUI
import AppKit

struct OnboardingView: View {
    var onFinished: () -> Void

    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shot")
                .font(.largeTitle.bold())
            stepContent
            Spacer()
            HStack {
                Button(String(localized: "跳过")) { onFinished() }
                    .keyboardShortcut(.cancelAction)
                if step > 0 {
                    Button(String(localized: "上一步")) { step -= 1 }
                }
                Spacer()
                Button(primaryTitle) {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 430)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear {
            permissions.stopPolling()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "欢迎使用 Shot"))
                    .font(.title2)
                Text(String(localized: "从菜单栏或快捷键开始截图。悬停点选窗口，拖拽框选区域；截取后可以直接标注、复制或保存。"))
                    .foregroundStyle(.secondary)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "屏幕录制权限"))
                    .font(.title2)
                Text(String(localized: "截取其他窗口内容需要系统「屏幕录制」权限。请在系统设置中允许 Shot 访问屏幕内容。"))
                    .foregroundStyle(.secondary)
                HStack {
                    Circle()
                        .fill(permissions.hasScreenRecording ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(permissionStatus)
                }
                HStack {
                    if permissions.screenRecordingNeedsRestart {
                        Button(String(localized: "退出并重新打开 Shot")) {
                            permissions.quitForPermissionRestart()
                        }
                    } else {
                        Button(String(localized: "请求权限")) {
                            permissions.requestScreenRecording()
                        }
                    }
                    Button(String(localized: "打开系统设置")) {
                        permissions.openScreenRecordingSettings()
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "保存位置与快捷键"))
                    .font(.title2)
                Text(String(localized: "默认保存到「图片/Shot」。主快捷键为 ⌃⌘A，可在设置里更改。"))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(settings.saveDirectoryURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(String(localized: "选择…")) { pickDirectory() }
                }
                HotkeyRecorder(action: .allInOne)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: return String(localized: "继续")
        case 1 where permissions.screenRecordingNeedsRestart:
            return String(localized: "退出并重新打开 Shot")
        case 1: return permissions.hasScreenRecording
            ? String(localized: "继续")
            : String(localized: "稍后设置")
        default: return String(localized: "开始使用")
        }
    }

    private func advance() {
        if step == 1, permissions.screenRecordingNeedsRestart {
            permissions.quitForPermissionRestart()
            return
        }
        if step < 2 {
            step += 1
        } else {
            onFinished()
        }
    }

    private var permissionStatus: String {
        if permissions.hasScreenRecording {
            return String(localized: "已授权")
        }
        if permissions.screenRecordingNeedsRestart {
            return String(localized: "已授权，退出并重新打开 Shot 后生效")
        }
        return String(localized: "尚未授权")
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryURL = url
        }
    }
}
