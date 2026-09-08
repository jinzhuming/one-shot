import AppKit
import ImageIO
import ShotKit

@MainActor
enum ScreenshotHistoryStore {
    private static var pendingFilenames = Set<String>()

    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Shot/History", isDirectory: true)
    }

    static func add(_ image: NSImage) {
        let directory = directory
        guard let cgImage = ImageExporter.cgImage(from: image) else { return }
        let preferred = ExportNaming.filename(fileExtension: "png")
        let filename = ExportNaming.uniqueFilename(preferred: preferred) { candidate in
            pendingFilenames.contains(candidate)
                || FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
        }
        pendingFilenames.insert(filename)
        let url = directory.appendingPathComponent(filename)
        let previous = normalized(AppSettings.shared.screenshotHistory)
        let next = ScreenshotHistory.inserting(
            ScreenshotHistoryItem(filename: filename),
            into: previous
        )
        let evicted = ScreenshotHistory.evictedFilenames(previous: previous, next: next)
        AppSettings.shared.screenshotHistory = next

        // Encoding and disk I/O are deliberately off the main actor. Keep the
        // filename reserved until the write completes so rapid captures in the
        // same second cannot overwrite one another.
        Task { @MainActor in
            let written = await Task.detached(priority: .utility) {
                guard let data = encodeScreenshotHistoryPNG(cgImage) else { return false }
                do {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    try data.write(to: url, options: .atomic)
                    for name in evicted {
                        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                    }
                    return true
                } catch {
                    return false
                }
            }.value

            pendingFilenames.remove(filename)
            if written {
                // A newer capture may have evicted this item while its write
                // was still running. Do not leave an unreferenced PNG behind.
                if !AppSettings.shared.screenshotHistory.contains(where: { $0.filename == filename }) {
                    try? FileManager.default.removeItem(at: url)
                }
            } else {
                AppSettings.shared.screenshotHistory.removeAll { $0.filename == filename }
            }
            StatusItemMenu.reload()
        }
    }

    static func items() -> [ScreenshotHistoryItem] {
        let directory = directory
        let cleaned = ScreenshotHistory.removingMissingFiles(
            from: AppSettings.shared.screenshotHistory,
            directory: directory
        ) { url in
            pendingFilenames.contains(url.lastPathComponent)
                || FileManager.default.fileExists(atPath: url.path)
        }
        let normalizedItems = normalized(cleaned)
        if normalizedItems != AppSettings.shared.screenshotHistory {
            // Menu content can be evaluated while SwiftUI is rendering. Defer
            // the published cleanup to avoid publishing during view updates.
            Task { @MainActor in
                let current = AppSettings.shared.screenshotHistory
                let currentCleaned = ScreenshotHistory.removingMissingFiles(
                    from: current,
                    directory: directory
                ) { url in
                    pendingFilenames.contains(url.lastPathComponent)
                        || FileManager.default.fileExists(atPath: url.path)
                }
                let currentNormalized = self.normalized(currentCleaned)
                if currentNormalized != current {
                    AppSettings.shared.screenshotHistory = currentNormalized
                }
            }
        }
        return normalizedItems
    }

    static func url(for item: ScreenshotHistoryItem) -> URL {
        directory.appendingPathComponent(item.filename)
    }

    static func image(for item: ScreenshotHistoryItem) -> NSImage? {
        NSImage(contentsOf: url(for: item))
    }

    private static func normalized(_ items: [ScreenshotHistoryItem]) -> [ScreenshotHistoryItem] {
        var seen = Set<String>()
        return items.filter { item in
            guard !item.filename.isEmpty,
                  item.filename == URL(fileURLWithPath: item.filename).lastPathComponent,
                  !item.filename.contains("/") else { return false }
            return seen.insert(item.filename).inserted
        }.prefix(ScreenshotHistory.limit).map { $0 }
    }
}

private func encodeScreenshotHistoryPNG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
