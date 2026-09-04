import Foundation

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case annotate
    case copy
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annotate: return String(localized: "打开标注")
        case .copy: return String(localized: "复制到剪贴板")
        case .save: return String(localized: "保存到文件")
        }
    }
}
