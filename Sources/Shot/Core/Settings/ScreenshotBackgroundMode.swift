import Foundation

enum ScreenshotBackgroundMode: String, CaseIterable, Identifiable {
    case desktop
    case custom
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop:
            return String(localized: "桌面壁纸")
        case .custom:
            return String(localized: "自定义图片")
        case .none:
            return String(localized: "不添加背景")
        }
    }
}
