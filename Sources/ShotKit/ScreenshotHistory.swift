import Foundation

public struct ScreenshotHistoryItem: Codable, Equatable, Sendable, Identifiable {
    public var filename: String
    public var createdAt: Date

    public var id: String { filename }

    public init(filename: String, createdAt: Date = Date()) {
        self.filename = filename
        self.createdAt = createdAt
    }
}

public enum ScreenshotHistory {
    public static let limit = 5

    public static func inserting(
        _ item: ScreenshotHistoryItem,
        into items: [ScreenshotHistoryItem]
    ) -> [ScreenshotHistoryItem] {
        var next = items.filter { $0.filename != item.filename }
        next.insert(item, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }

    public static func removingMissingFiles(
        from items: [ScreenshotHistoryItem],
        directory: URL,
        exists: (URL) -> Bool
    ) -> [ScreenshotHistoryItem] {
        items.filter { exists(directory.appendingPathComponent($0.filename)) }
    }

    public static func evictedFilenames(
        previous: [ScreenshotHistoryItem],
        next: [ScreenshotHistoryItem]
    ) -> [String] {
        let kept = Set(next.map(\.filename))
        return previous.map(\.filename).filter { !kept.contains($0) }
    }
}
