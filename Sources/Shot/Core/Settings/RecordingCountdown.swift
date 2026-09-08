import Foundation

enum RecordingCountdown: Int, CaseIterable, Identifiable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "关")
        case .three: return String(localized: "3 秒")
        case .five: return String(localized: "5 秒")
        case .ten: return String(localized: "10 秒")
        }
    }
}
