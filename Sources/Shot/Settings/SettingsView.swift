import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var loginItem = LoginItemService.shared

    enum Page: String, CaseIterable, Identifiable {
        case general, screenshots, recording, output, shortcuts
        var id: Self { self }
        var title: String {
            switch self {
            case .general: String(localized: "通用")
            case .screenshots: String(localized: "截图与标注")
            case .recording: String(localized: "录屏")
            case .output: String(localized: "输出")
            case .shortcuts: String(localized: "快捷键")
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .screenshots: "camera"
            case .recording: "record.circle"
            case .output: "square.and.arrow.down"
            case .shortcuts: "keyboard"
            }
        }
    }

    @State private var selection: Page? = .general

    init(initialPage: Page = .general) {
        _selection = State(initialValue: initialPage)
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 190)
            .accessibilityLabel(String(localized: "设置分类"))
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text((selection ?? .general).title)
                    .font(.title2.weight(.semibold))
                    .scenePadding([.top, .horizontal])
                    .accessibilityAddTraits(.isHeader)
                Group {
                    switch selection ?? .general {
                    case .general: generalTab
                    case .screenshots: screenshotsTab
                    case .recording: recordingTab
                    case .output: outputTab
                    case .shortcuts: shortcutsTab
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: InterfaceMetrics.settingsMinimumSize.width,
               minHeight: InterfaceMetrics.settingsMinimumSize.height)
        .background {
            SettingsWindowConfigurator()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            permissions.startPolling()
            loginItem.refresh()
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear { permissions.stopPolling() }
    }

    private var generalTab: some View {
        Form {
            Section(String(localized: "截图浮层")) {
                Toggle(String(localized: "模式条更通透"), isOn: $settings.useLightweightCaptureHUD)
                Text(String(localized: "让截图模式条更通透。开启系统“减少透明度”后使用实色背景。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "启动")) {
                Toggle(String(localized: "登录时打开"), isOn: loginEnabled)
            }

            Section(String(localized: "权限")) {
                permissionRow(
                    granted: permissions.hasScreenRecording,
                    needsRestart: permissions.screenRecordingNeedsRestart,
                    grantedText: String(localized: "屏幕录制已授权"),
                    pendingText: String(localized: "已授权，退出并重新打开 Shot 后生效"),
                    deniedText: String(localized: "屏幕录制未授权"),
                    openSettings: { permissions.openScreenRecordingSettings() }
                )
                microphoneRow
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

    private var shortcutsTab: some View {
        Form {
            Section {
                HotkeyRecorder(action: .allInOne)
                HotkeyRecorder(action: .recording)
                HotkeyRecorder(action: .captureArea)
                HotkeyRecorder(action: .captureWindow)
                HotkeyRecorder(action: .captureFullscreen)
                HotkeyRecorder(action: .scrolling)
                HotkeyRecorder(action: .capturePreviousRegion)
            } header: {
                Text(String(localized: "全局快捷键"))
            } footer: {
                Text(String(localized: "若快捷键被系统或其他 App 占用，此处会显示「未生效」。"))
            }
            Section {
                OverlayToggleHotkeyRecorder()
            } header: {
                Text(String(localized: "截图时"))
            } footer: {
                Text(String(localized: "未框选时按该快捷键或点击，可在区域和窗口之间切换。拖拽选区时仍按空格移动选区。"))
            }
            Section {
                Text(String(localized: "标注：V 选择，C 裁剪，1–4 形状，5 画笔，6 荧光笔，7 文字，K 气泡，8 序号，9 马赛克，0 聚光。⌘D 复制标注，Delete 删除。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "编辑器"))
            }
        }
        .formStyle(.grouped)
    }

    private var screenshotsTab: some View {
        Form {
            Section(String(localized: "编辑器")) {
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
            }
            Section(String(localized: "窗口截图")) {
                Toggle(String(localized: "窗口截图包含阴影"), isOn: $settings.includeWindowShadow)
            }
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

    private var outputTab: some View {
        Form {
            Section(String(localized: "保存")) {
                Picker(String(localized: "截图格式"), selection: $settings.saveFormat) {
                    ForEach(SaveFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Toggle(String(localized: "每次询问保存位置"), isOn: $settings.askWhereToSave)
                LabeledContent(String(localized: "保存位置")) {
                    Button(String(localized: "选择…")) { pickDirectory() }
                        .help(String(localized: "选择截图与录屏的保存文件夹"))
                }
                Text(settings.saveDirectoryURL.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(settings.saveDirectoryURL.path)
            }
            Section {
                Toggle(String(localized: "保存或标注后同时复制到剪贴板"), isOn: $settings.copyOnComplete)
            } header: {
                Text(String(localized: "剪贴板"))
            } footer: {
                Text(String(localized: "保存截图或完成标注后，会同时把最终图片复制到剪贴板。"))
            }
        }
        .formStyle(.grouped)
    }

    private var recordingTab: some View {
        Form {
            Section(String(localized: "声音")) {
                Toggle(String(localized: "录制系统声音"), isOn: $settings.captureSystemAudio)
                Toggle(String(localized: "录制麦克风"), isOn: microphoneCapture)
                Text(String(localized: "麦克风需要系统权限。未授权时仍会继续录屏，只是不包含人声。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "录制过程")) {
                Picker(String(localized: "开始前倒计时"), selection: $settings.recordingCountdown) {
                    ForEach(RecordingCountdown.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Toggle(String(localized: "高亮鼠标点击"), isOn: $settings.highlightClicks)
                Text(String(localized: "倒计时不会写入成片。点击高亮会显示在录制画面中，便于演示。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var microphoneCapture: Binding<Bool> {
        Binding(
            get: { settings.captureMicrophone },
            set: { enabled in
                settings.captureMicrophone = enabled
                if enabled, !permissions.hasMicrophone {
                    Task {
                        let granted = await permissions.requestMicrophone()
                        if !granted {
                            settings.captureMicrophone = false
                        }
                    }
                }
            }
        )
    }

    private var microphoneRow: some View {
        permissionRow(
            granted: permissions.hasMicrophone,
            needsRestart: false,
            grantedText: String(localized: "麦克风已授权"),
            pendingText: "",
            deniedText: String(localized: "麦克风未授权"),
            openSettings: { permissions.openMicrophoneSettings() }
        )
    }

    private func permissionRow(
        granted: Bool,
        needsRestart: Bool,
        grantedText: String,
        pendingText: String,
        deniedText: String,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.spacing) {
            Label(granted ? grantedText : (needsRestart ? pendingText : deniedText),
                  systemImage: granted ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if needsRestart {
                Button(String(localized: "退出并重新打开 Shot")) {
                    permissions.quitForPermissionRestart()
                }
            } else {
                Button(String(localized: "打开系统设置"), action: openSettings)
                    .help(String(localized: "在系统设置中管理此权限"))
            }
        }
        .padding(.vertical, 2)
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
