import SwiftUI
import AppKit

struct OnboardingView: View {
    var onFinished: () -> Void

    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var step = 0

    init(initialStep: Int = 0, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        _step = State(initialValue: min(2, max(0, initialStep)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                Label("Shot", systemImage: "viewfinder")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(String(localized: "第 \(step + 1) 步，共 3 步"))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step + 1), total: 3)
                .accessibilityLabel(String(localized: "设置进度"))
                .accessibilityValue(String(localized: "第 \(step + 1) 步，共 3 步"))
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 8) {
                Button(String(localized: "跳过")) { onFinished() }
                    .keyboardShortcut(.cancelAction)
                    .help(String(localized: "稍后在设置中完成配置"))
                if step > 0 {
                    Button(String(localized: "上一步")) { step -= 1 }
                }
                Spacer()
                Button(primaryTitle) { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .scenePadding()
        .frame(width: 520, height: 460)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "欢迎使用 Shot"))
                    .font(.title2)
                Text(String(localized: "从菜单栏或快捷键开始截图、滚动截图或录屏。悬停点选窗口，拖拽框选区域；截取后可以直接标注、复制或保存。"))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    onboardingHint(systemImage: "rectangle.dashed", title: String(localized: "框选区域"))
                    onboardingHint(systemImage: "macwindow", title: String(localized: "点选窗口"))
                    onboardingHint(systemImage: "rectangle.bottomhalf.inset.filled", title: String(localized: "底部切换模式"))
                }
                .padding(.top, 4)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "屏幕录制权限"))
                    .font(.title2)
                Text(String(localized: "截取其他窗口内容需要系统「屏幕录制」权限。请在系统设置中允许 Shot 访问屏幕内容。"))
                    .foregroundStyle(.secondary)
                Label(permissionStatus, systemImage: permissions.hasScreenRecording
                      ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if permissions.screenRecordingNeedsRestart {
                        Button(String(localized: "退出并重新打开 Shot")) {
                            permissions.quitForPermissionRestart()
                        }
                    } else if !permissions.hasScreenRecording {
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
                Text(String(localized: "选择保存文件夹，并设置常用快捷键。之后也可以在设置中更改。"))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(settings.saveDirectoryURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(String(localized: "选择…")) { pickDirectory() }
                }
                Divider()
                HotkeyRecorder(action: .allInOne)
                HotkeyRecorder(action: .capturePreviousRegion)
                HotkeyRecorder(action: .recording)
            }
        }
    }

    private func onboardingHint(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 28)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
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
