import AppKit
import Carbon
import ShotKit
import SwiftUI

enum HotkeyAction: String, CaseIterable, Identifiable {
    case allInOne
    case recording
    case captureArea
    case captureWindow
    case captureFullscreen
    case scrolling
    case capturePreviousRegion

    var id: String { rawValue }

    var carbonID: UInt32 {
        switch self {
        case .allInOne: return 1
        case .recording: return 2
        case .captureArea: return 3
        case .captureWindow: return 4
        case .captureFullscreen: return 5
        case .scrolling: return 6
        case .capturePreviousRegion: return 7
        }
    }

    var title: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .recording: return String(localized: "录屏")
        case .captureArea: return String(localized: "截取区域")
        case .captureWindow: return String(localized: "截取窗口")
        case .captureFullscreen: return String(localized: "截取全屏")
        case .scrolling: return String(localized: "滚动截图")
        case .capturePreviousRegion: return String(localized: "截取上次区域")
        }
    }

    var captureMode: CaptureMode {
        switch self {
        case .allInOne: return .allInOne
        case .recording: return .allInOne
        case .captureArea: return .area
        case .captureWindow: return .window
        case .captureFullscreen: return .fullscreen
        case .scrolling: return .area
        case .capturePreviousRegion: return .area
        }
    }

    var defaultsKey: String { "hotkey.\(rawValue)" }
}

struct HotkeyRecorder: View {
    let action: HotkeyAction
    @ObservedObject private var center = HotkeyCenter.shared
    @State private var isRecording = false

    var body: some View {
        let _ = center.registrationRevision
        HStack {
            Text(action.title)
            Spacer()
            Button {
                isRecording.toggle()
            } label: {
                Text(buttonTitle)
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .help(String(localized: "点击录制快捷键，按 Esc 取消"))
            .accessibilityLabel(String(localized: "\(action.title)快捷键"))
            .accessibilityValue(buttonTitle)
            .accessibilityHint(String(localized: "点击录制新的快捷键"))
            if center.hotkey(for: action) != nil, !isRecording {
                Button(String(localized: "清除")) {
                    center.set(nil, for: action)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(String(localized: "清除\(action.title)快捷键"))
                .accessibilityValue(String(localized: "清除"))
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                center.beginRecording(for: action) { _ in
                    isRecording = false
                }
            } else {
                center.endRecording()
            }
        }
    }

    private var buttonTitle: String {
        if isRecording {
            return String(localized: "按下快捷键…")
        }
        guard let hotkey = center.hotkey(for: action) else {
            return String(localized: "未设置")
        }
        if center.isRegistered(action) {
            return hotkey.localizedDisplayString
        }
        return "\(hotkey.localizedDisplayString) · \(String(localized: "未生效"))"
    }
}

struct OverlayToggleHotkeyRecorder: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var center = HotkeyCenter.shared
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(String(localized: "区域与窗口切换"))
            Spacer()
            Button {
                isRecording.toggle()
            } label: {
                Text(buttonTitle)
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .help(String(localized: "截图时在区域和窗口之间切换"))
            .accessibilityLabel(String(localized: "区域与窗口切换快捷键"))
            .accessibilityValue(buttonTitle)
            .accessibilityHint(String(localized: "点击录制新的快捷键"))
            if !settings.areaWindowToggleHotkey.conflicts(with: .defaultAreaWindowToggle), !isRecording {
                Button(String(localized: "重置")) {
                    settings.areaWindowToggleHotkey = .defaultAreaWindowToggle
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(String(localized: "重置区域与窗口切换快捷键"))
                .accessibilityValue(String(localized: "重置"))
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                center.beginRecordingOverlayToggle { hotkey in
                    if let hotkey {
                        settings.areaWindowToggleHotkey = hotkey
                    }
                    isRecording = false
                }
            } else {
                center.endRecording()
            }
        }
    }

    private var buttonTitle: String {
        if isRecording {
            return String(localized: "按下快捷键…")
        }
        return settings.areaWindowToggleHotkey.localizedDisplayString
    }
}

extension Hotkey {
    var localizedDisplayString: String {
        if keyCode == 49 {
            return displayString.replacingOccurrences(of: "Space", with: String(localized: "空格"))
        }
        return displayString
    }
}

@MainActor
final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()

    @Published private(set) var registrationRevision = 0

    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var recordingMonitor: Any?
    private var recordingAction: HotkeyAction?
    private var recordingHandler: ((Hotkey?) -> Void)?
    private var recordingRequiresModifiers = true
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func register() {
        installHandlerIfNeeded()
        for action in HotkeyAction.allCases {
            register(hotkey(for: action), for: action)
        }
    }

    func isRegistered(_ action: HotkeyAction) -> Bool {
        refs[action] != nil
    }

    func hotkey(for action: HotkeyAction) -> Hotkey? {
        if let data = defaults.data(forKey: action.defaultsKey) {
            if data.isEmpty { return nil }
            return try? JSONDecoder().decode(Hotkey.self, from: data)
        }
        if action == .allInOne {
            return .defaultAllInOne
        }
        if action == .recording {
            return .defaultRecording
        }
        if action == .scrolling {
            return .defaultScrolling
        }
        if action == .capturePreviousRegion {
            return .defaultCapturePreviousRegion
        }
        return nil
    }

    func set(_ hotkey: Hotkey?, for action: HotkeyAction) {
        if let hotkey {
            for other in HotkeyAction.allCases where other != action {
                if let existing = self.hotkey(for: other), existing.conflicts(with: hotkey) {
                    write(nil, for: other)
                    register(nil, for: other)
                }
            }
        }
        write(hotkey, for: action)
        register(hotkey, for: action)
        StatusItemMenu.reload()
    }

    private func write(_ hotkey: Hotkey?, for action: HotkeyAction) {
        if let hotkey, let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: action.defaultsKey)
        } else if action == .allInOne {
            defaults.set(Data(), forKey: action.defaultsKey)
        } else {
            defaults.removeObject(forKey: action.defaultsKey)
        }
    }

    func beginRecording(for action: HotkeyAction, completion: @escaping (Hotkey?) -> Void) {
        startRecording(action: action, requiresModifiers: true, completion: completion)
    }

    func beginRecordingOverlayToggle(completion: @escaping (Hotkey?) -> Void) {
        startRecording(action: nil, requiresModifiers: false, completion: completion)
    }

    func endRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        recordingAction = nil
        recordingHandler = nil
        recordingRequiresModifiers = true
    }

    private func startRecording(
        action: HotkeyAction?,
        requiresModifiers: Bool,
        completion: @escaping (Hotkey?) -> Void
    ) {
        endRecording()
        recordingAction = action
        recordingRequiresModifiers = requiresModifiers
        recordingHandler = completion
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecording(event)
            return nil
        }
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == 53 {
            let handler = recordingHandler
            endRecording()
            handler?(nil)
            return
        }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if recordingRequiresModifiers {
            let isFunctionKey = (96...111).contains(event.keyCode) || (118...122).contains(event.keyCode)
            guard !mods.isEmpty || isFunctionKey else { return }
        }
        let hotkey = Hotkey(
            keyCode: event.keyCode,
            modifierRaw: mods.rawValue,
            character: event.charactersIgnoringModifiers ?? ""
        )
        if hotkey.isSystemScreenshotShortcut {
            NSSound.beep()
            return
        }
        if !recordingRequiresModifiers {
            if hotkey.isReservedOverlayShortcut || conflictsWithGlobalHotkey(hotkey) {
                NSSound.beep()
                return
            }
        } else if let action = recordingAction {
            set(hotkey, for: action)
        }
        let handler = recordingHandler
        endRecording()
        handler?(hotkey)
    }

    private func conflictsWithGlobalHotkey(_ hotkey: Hotkey) -> Bool {
        HotkeyAction.allCases.contains { action in
            guard let existing = self.hotkey(for: action) else { return false }
            return existing.conflicts(with: hotkey)
        }
    }

    private func register(_ hotkey: Hotkey?, for action: HotkeyAction) {
        if let existing = refs[action] {
            UnregisterEventHotKey(existing)
            refs[action] = nil
        }
        guard let hotkey else {
            registrationRevision += 1
            return
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("SHOT"), id: action.carbonID)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            refs[action] = ref
        }
        registrationRevision += 1
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), shotHotKeyHandler, 1, &spec, nil, &handlerRef)
    }

    fileprivate static func handle(id: UInt32) {
        guard let action = HotkeyAction.allCases.first(where: { $0.carbonID == id }) else { return }
        if action == .recording {
            AppCoordinator.shared.toggleRecording()
        } else if action == .scrolling {
            AppCoordinator.shared.startScrollingCapture()
        } else if action == .capturePreviousRegion {
            CaptureSession.shared.capturePreviousRegion()
        } else {
            AppCoordinator.shared.startCapture(action.captureMode)
        }
    }
}

private func shotHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    Task { @MainActor in
        HotkeyCenter.handle(id: hotKeyID.id)
    }
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.utf8.prefix(4) {
        result = (result << 8) + OSType(scalar)
    }
    return result
}
