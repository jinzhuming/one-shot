import Foundation
import OSLog

enum Diagnostics {
    static let lifecycle = Logger(subsystem: "com.jinzhuming.shot", category: "lifecycle")
    static let exports = Logger(subsystem: "com.jinzhuming.shot", category: "exports")
    static let performance = OSSignposter(subsystem: "com.jinzhuming.shot", category: "performance")
}
