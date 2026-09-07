import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var loginItem = LoginItemService.shared

    var body: some View {
        TabView {
            Tab(String(localized: "通用"), systemImage: "gearshape") { generalTab }
            Tab(String(localized: "快捷键"), systemImage: "keyboard") { shortcutsTab }
            Tab(String(localized: "截图"), systemImage: "camera") { screenshotsTab }
        }
        .scenePadding()
        .frame(width: 520, height: 500)
        .background {
            SettingsWindowConfigurator()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            permissions.refresh()
            loginItem.refresh()
            NSApp.setActivationPolicy(.regular)
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker(String(localized: "截图后"), selection: $settings.afterCaptureAction) {
                    ForEach(AfterCaptureAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                Picker(String(localized: "标注位置"), selection: $settings.annotationWindowPlacement) {
                    ForEach(AnnotationWindowPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                Text(String(localized: "原位置空间不足时，会自动缩放并移入当前显示器的可见区域；独立窗口可拖拽缩放。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "触控板按住 ⌘ 时缩放画布"), isOn: $settings.annotationZoomWithCommandScroll)
                Text(String(localized: "鼠标滚轮默认缩放，触控板滚动手势默认平移。开启后，触控板也可按住 ⌘ 用滚轮缩放。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "保存或标注后同时复制到剪贴板"), isOn: $settings.copyOnComplete)
                if settings.afterCaptureAction != .copy, settings.copyOnComplete {
                    Text(String(localized: "保存截图或完成标注后，会同时把最终图片复制到剪贴板。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "外观")) {
                Toggle(String(localized: "使用轻量透明提示"), isOn: $settings.useLightweightCaptureHUD)
                Text(String(localized: "开启后，截图模式条使用更透明的原生 HUD 外观。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "登录时打开"), isOn: loginEnabled)
            }

            Section(String(localized: "权限")) {
                HStack {
                    Circle()
                        .fill(permissions.hasScreenRecording ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(permissionStatus)
                    Spacer()
                    if permissions.screenRecordingNeedsRestart {
                        Button(String(localized: "退出并重新打开 Shot")) {
                            permissions.quitForPermissionRestart()
                        }
                    } else {
                        Button(String(localized: "打开系统设置")) {
                            permissions.openScreenRecordingSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var loginEnabled: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }

    private var permissionStatus: String {
        if permissions.hasScreenRecording {
            return String(localized: "屏幕录制已授权")
        }
        if permissions.screenRecordingNeedsRestart {
            return String(localized: "已授权，退出并重新打开 Shot 后生效")
        }
        return String(localized: "屏幕录制未授权")
    }

    private var shortcutsTab: some View {
        Form {
            Section {
                HotkeyRecorder(action: .allInOne)
                HotkeyRecorder(action: .recording)
                HotkeyRecorder(action: .captureArea)
                HotkeyRecorder(action: .captureWindow)
                HotkeyRecorder(action: .captureFullscreen)
                HotkeyRecorder(action: .scrolling)
            } footer: {
                Text(String(localized: "若快捷键被系统或其他 App 占用，此处会显示「未生效」。录屏保存为 MP4，当前不包含系统音频或麦克风。"))
            }
            Section {
                OverlayToggleHotkeyRecorder()
            } header: {
                Text(String(localized: "截图时"))
            } footer: {
                Text(String(localized: "未框选时按该快捷键或点击，可在区域和窗口之间切换。拖拽选区时仍按空格移动选区。"))
            }
        }
        .formStyle(.grouped)
    }

    private var screenshotsTab: some View {
        Form {
            Picker(String(localized: "格式"), selection: $settings.saveFormat) {
                ForEach(SaveFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            Toggle(String(localized: "每次询问保存位置"), isOn: $settings.askWhereToSave)
            HStack {
                Text(String(localized: "保存位置"))
                Spacer()
                Text(settings.saveDirectoryURL.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(String(localized: "选择…")) { pickDirectory() }
            }
            Toggle(String(localized: "窗口截图包含阴影"), isOn: $settings.includeWindowShadow)
            Section(String(localized: "窗口截图背景")) {
                Picker(String(localized: "背景"), selection: $settings.screenshotBackgroundMode) {
                    ForEach(ScreenshotBackgroundMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if settings.screenshotBackgroundMode == .custom {
                    HStack {
                        Text(settings.customScreenshotBackgroundURL?.lastPathComponent
                            ?? String(localized: "未选择图片"))
                            .foregroundStyle(settings.customScreenshotBackgroundURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "选择图片…")) { pickBackgroundImage() }
                            .help(String(localized: "选择用于窗口截图背景的图片。"))
                    }
                    if settings.customScreenshotBackgroundURL == nil {
                        Text(String(localized: "请选择一张背景图片；未选择时不会添加背景。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(String(localized: "窗口截图会自动留出边距，并使用截图所在显示器的桌面壁纸或自定义图片。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryURL = url
        }
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.message = String(localized: "选择用于窗口截图背景的图片。")
        if panel.runModal() == .OK, let url = panel.url {
            settings.customScreenshotBackgroundURL = url
            settings.screenshotBackgroundMode = .custom
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.title = String(localized: "设置")
        window.identifier = NSUserInterfaceItemIdentifier(SettingsWindowIdentity.identifier)
        window.minSize = NSSize(width: 520, height: 400)
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
    }
}
