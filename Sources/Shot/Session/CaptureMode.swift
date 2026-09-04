import Foundation
import ShotKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case allInOne
    case area
    case window
    case fullscreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .area: return String(localized: "区域")
        case .window: return String(localized: "窗口")
        case .fullscreen: return String(localized: "全屏")
        }
    }

    var allowsWindowClick: Bool {
        self == .allInOne || self == .window
    }

    var allowsAreaDrag: Bool {
        self == .allInOne || self == .area
    }

    var overlayKind: OverlayModeKind {
        switch self {
        case .area: return .area
        case .window: return .window
        case .allInOne, .fullscreen: return .other
        }
    }
}

enum OverlayModeHint {
    static func caption(for mode: CaptureMode, toggleKey: String) -> String? {
        switch mode {
        case .allInOne:
            return String(localized: "点击窗口 · 拖拽区域")
        case .area:
            return String(localized: "拖拽框选 · \(toggleKey) 或点击切换窗口")
        case .window:
            return String(localized: "点击窗口 · \(toggleKey) 或拖拽切换区域")
        case .fullscreen:
            return nil
        }
    }
}
