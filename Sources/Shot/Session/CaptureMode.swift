import Foundation
import ShotKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case allInOne
    case area
    case window
    case fullscreen

    var id: String { rawValue }

    static let selectableModes: [CaptureMode] = [.area, .window, .fullscreen]

    /// The mode used by the interactive overlay. All-in-One is a launch
    /// shortcut, not a fourth selectable state in the mode bar.
    var interactiveMode: CaptureMode {
        self == .allInOne ? .area : self
    }

    var title: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .area: return String(localized: "区域")
        case .window: return String(localized: "窗口")
        case .fullscreen: return String(localized: "全屏")
        }
    }

    var allowsWindowClick: Bool {
        interactiveMode == .window
    }

    var allowsAreaDrag: Bool {
        interactiveMode == .area
    }

    var overlayKind: OverlayModeKind {
        switch interactiveMode {
        case .area: return .area
        case .window: return .window
        case .fullscreen: return .other
        case .allInOne: return .area
        }
    }
}

enum OverlayModeHint {
    static func caption(for mode: CaptureMode, toggleKey: String) -> String? {
        switch mode {
        case .allInOne:
            return caption(for: .area, toggleKey: toggleKey)
        case .area:
            return String(localized: "拖拽框选 · Shift 等比例 · 空格移动 · Esc 取消 · \(toggleKey) 切换窗口")
        case .window:
            return String(localized: "点击窗口 · 拖拽区域 · Esc 取消 · \(toggleKey) 切换")
        case .fullscreen:
            return nil
        }
    }
}
