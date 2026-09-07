import Foundation

enum AnnotationWindowPlacement: String, CaseIterable, Identifiable {
    case inPlace
    case centered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inPlace:
            return String(localized: "原位置")
        case .centered:
            return String(localized: "独立窗口（居中）")
        }
    }
}
