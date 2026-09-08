import AppKit
import ImageIO
import ShotKit

@MainActor
enum ScreenshotHistoryStore {
    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Shot/History", isDirectory: true)
    }

    static let repository = ScreenshotHistoryRepository(settings: .shared, directory: directory)
    static func add(_ image: NSImage) {
        guard let image = ImageExporter.cgImage(from: image) else { return }
        repository.add(image)
    }
    static func items() -> [ScreenshotHistoryItem] { repository.items }
    static func url(for item: ScreenshotHistoryItem) -> URL { directory.appendingPathComponent(item.filename) }
    static func image(for item: ScreenshotHistoryItem) -> NSImage? { NSImage(contentsOf: url(for: item)) }
}

/// A bounded FIFO. At most one encoder and five pending images are retained.
/// The menu sees only committed files; reading the menu never mutates settings
/// or performs filesystem I/O.
@MainActor
final class ScreenshotHistoryRepository {
    typealias Writer = (CGImage, URL) async throws -> URL
    private let settings: AppSettings
    private let directory: URL
    private let writer: Writer
    private var pending: [CGImage] = []
    private var worker: Task<Void, Never>?
    private(set) var items: [ScreenshotHistoryItem]
    var pendingCount: Int { pending.count }

    init(settings: AppSettings, directory: URL, writer: @escaping Writer = { image, directory in
        try await BackgroundWork.run(priority: .utility) {
            guard let data = encodeScreenshotHistoryPNG(image) else { throw ImageExporter.ExportError.encodingFailed }
            return try AtomicFileWriter.write(data, to: .automatic(
                directory: directory, filename: ExportNaming.filename(fileExtension: "png")
            ))
        }
    }) {
        self.settings = settings
        self.directory = directory
        self.writer = writer
        self.items = Self.normalized(settings.screenshotHistory)
    }

    func add(_ image: CGImage) {
        pending.append(image)
        if pending.count > ScreenshotHistory.limit { pending.removeFirst() }
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.worker = nil }
            while !self.pending.isEmpty, !Task.isCancelled {
                let image = self.pending.removeFirst()
                do {
                    let url = try await self.writer(image, self.directory)
                    let previous = self.items
                    let next = ScreenshotHistory.inserting(ScreenshotHistoryItem(filename: url.lastPathComponent), into: previous)
                    self.items = next
                    self.settings.screenshotHistory = next
                    StatusItemMenu.reload()
                    let evicted = ScreenshotHistory.evictedFilenames(previous: previous, next: next)
                    let directory = self.directory
                    _ = try? await BackgroundWork.run(priority: .utility) {
                        for name in evicted { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    Diagnostics.exports.error("History write failed")
                }
            }
        }
    }

    func waitUntilIdle() async { await worker?.value }

    func releasePendingImages() { pending.removeAll() }

    func reconcile() async {
        let previous = items
        let directory = directory
        let present = (try? await BackgroundWork.run(priority: .utility) {
            Set(previous.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.filename).path) }.map(\.filename))
        }) ?? Set(previous.map(\.filename))
        // Preserve any new writes that completed while the filesystem was read.
        let checked = Set(previous.map(\.filename))
        items.removeAll { checked.contains($0.filename) && !present.contains($0.filename) }
        settings.screenshotHistory = items
        StatusItemMenu.reload()
    }

    private static func normalized(_ items: [ScreenshotHistoryItem]) -> [ScreenshotHistoryItem] {
        var seen = Set<String>()
        return Array(items.filter { item in
            !item.filename.isEmpty && item.filename != "." && item.filename != ".."
                && item.filename == URL(fileURLWithPath: item.filename).lastPathComponent
                && !item.filename.contains("/") && seen.insert(item.filename).inserted
        }.prefix(ScreenshotHistory.limit))
    }
}

private func encodeScreenshotHistoryPNG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
