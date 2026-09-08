import Foundation
import Testing
@testable import ShotKit

@Test func screenshotHistoryKeepsFiveMostRecentItemsAndEvictsTheRest() {
    let first = (1...6).map { index in
        ScreenshotHistoryItem(filename: "Shot \(index).png", createdAt: Date(timeIntervalSince1970: Double(index)))
    }
    var items: [ScreenshotHistoryItem] = []
    for item in first {
        items = ScreenshotHistory.inserting(item, into: items)
    }
    #expect(items.count == 5)
    #expect(items.map(\.filename) == [
        "Shot 6.png",
        "Shot 5.png",
        "Shot 4.png",
        "Shot 3.png",
        "Shot 2.png"
    ])

    let next = ScreenshotHistory.inserting(
        ScreenshotHistoryItem(filename: "Shot 6.png", createdAt: Date()),
        into: items
    )
    #expect(next.first?.filename == "Shot 6.png")
    #expect(next.count == 5)

    let evicted = ScreenshotHistory.evictedFilenames(previous: items, next: next)
    #expect(evicted.isEmpty)

    let trimmed = ScreenshotHistory.removingMissingFiles(
        from: next,
        directory: URL(fileURLWithPath: "/tmp")
    ) { url in
        url.lastPathComponent != "Shot 4.png"
    }
    #expect(!trimmed.contains { $0.filename == "Shot 4.png" })
    #expect(ScreenshotHistory.evictedFilenames(previous: next, next: trimmed).contains("Shot 4.png"))
}

@Test func screenshotHistoryFilenamesFollowExportNaming() {
    let date = Date(timeIntervalSince1970: 1_704_067_200)
    let name = ExportNaming.filename(
        fileExtension: "png",
        date: date,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
    #expect(name.hasPrefix("Shot "))
    #expect(name.hasSuffix(".png"))
}

@Test func pixelSamplingFormatsHexAndMapsOverlayCoordinates() {
    #expect(PixelSampling.hex(red: 10, green: 32, blue: 255) == "#0A20FF")
    let display = PixelSampling.displayPoint(
        global: CGPoint(x: 120, y: 80),
        screenFrame: CGRect(x: 100, y: 40, width: 800, height: 600)
    )
    #expect(display == CGPoint(x: 20, y: 40))
}
