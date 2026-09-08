import AppKit
import Foundation
import ShotKit
import Testing
@testable import Shot

@Test func concurrentAutomaticExportsNeverOverwriteEachOther() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = try await withThrowingTaskGroup(of: URL.self) { group in
        for value in 0..<40 {
            group.addTask {
                try await BackgroundWork.run {
                    try AtomicFileWriter.write(Data("image-\(value)".utf8), to: .automatic(directory: directory, filename: "Shot.png"))
                }
            }
        }
        var urls: [URL] = []
        for try await url in group { urls.append(url) }
        return urls
    }
    #expect(Set(urls).count == 40)
    let contents = try Set(urls.map { try String(contentsOf: $0, encoding: .utf8) })
    #expect(contents.count == 40)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 40)
}

@Test func failedAtomicExportPreservesExistingFileAndRemovesTemporaryFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = directory.appendingPathComponent("existing.png")
    try Data("original".utf8).write(to: original)
    #expect(throws: (any Error).self) {
        try AtomicFileWriter.write(Data("new".utf8), to: .chosen(original.appendingPathComponent("invalid.png")))
    }
    #expect(try Data(contentsOf: original) == Data("original".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["existing.png"])
}

@Test func cancellingBackgroundWorkPreventsItsNextStage() async throws {
    let gate = DispatchSemaphore(value: 0)
    let began = DispatchSemaphore(value: 0)
    let task = Task {
        try await BackgroundWork.run {
            began.signal()
            gate.wait()
            try Task.checkCancellation()
            return 42
        }
    }
    _ = try await BackgroundWork.run { began.wait() }
    task.cancel()
    gate.signal()
    do { _ = try await task.value; Issue.record("Cancelled worker returned a result") }
    catch { #expect(error is CancellationError) }
}

@MainActor private struct FailingRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String { throw OCRService.RecognitionError.failed }
}

@MainActor private struct LateRecognizer: TextRecognizing {
    let wait: () async -> Void
    func recognize(_ image: CGImage) async throws -> String { await wait(); return "late text" }
}

@MainActor private func outputFixture() -> NSImage {
    let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    return NSImage(cgImage: context.makeImage()!, size: CGSize(width: 32, height: 32))
}

@Test @MainActor func ocrFailureIsNotReportedAsEmptyText() async {
    await #expect(throws: OCRService.RecognitionError.self) {
        try await OCRService.recognizeText(in: outputFixture(), recognizer: FailingRecognizer())
    }
}

@Test @MainActor func cancelledOutputDiscardsLateOCRResults() async throws {
    var continuation: CheckedContinuation<Void, Never>?
    var began = false
    let service = EditorOutputService(recognizer: LateRecognizer(wait: {
        began = true
        await withCheckedContinuation { continuation = $0 }
    }))
    let snapshot = AnnotationRenderSnapshot(document: AnnotationDocument(baseImage: outputFixture()))!
    let task = Task { try await service.perform(.ocr, snapshot: snapshot, format: .png, destination: nil) }
    while !began { await Task.yield() }
    task.cancel()
    continuation?.resume()
    do { _ = try await task.value; Issue.record("Late OCR escaped cancellation") }
    catch { #expect(error is CancellationError) }
}

@Test @MainActor func renderSnapshotDoesNotFollowChangesToLiveNSImage() throws {
    let image = outputFixture()
    let snapshot = AnnotationRenderSnapshot(document: AnnotationDocument(baseImage: image))!
    image.size = CGSize(width: 400, height: 800)
    image.removeRepresentation(image.representations[0])
    let rendered = try #require(snapshot.renderedCGImage())
    #expect(rendered.width == 32 && rendered.height == 32)
    #expect(snapshot.size == CGSize(width: 32, height: 32))
}

@Test @MainActor func historyPublishesOnlyCompletedWritesAndBoundsPendingImages() async throws {
    let name = "ShotTests.History.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var continuation: CheckedContinuation<Void, Never>?
    var count = 0
    let repository = ScreenshotHistoryRepository(settings: settings, directory: directory) { _, directory in
        count += 1
        if count == 1 { await withCheckedContinuation { continuation = $0 } }
        if count == 2 { throw CocoaError(.fileWriteOutOfSpace) }
        return directory.appendingPathComponent("\(count).png")
    }
    let image = ImageExporter.cgImage(from: outputFixture())!
    repository.add(image)
    while continuation == nil { await Task.yield() }
    for _ in 0..<100 { repository.add(image) }
    #expect(repository.pendingCount == 5)
    #expect(repository.items.isEmpty)
    #expect(settings.screenshotHistory.isEmpty)
    continuation?.resume()
    await repository.waitUntilIdle()
    #expect(count == 6)
    #expect(repository.items.count == 5)
    #expect(!repository.items.contains { $0.filename == "2.png" })
    #expect(settings.screenshotHistory == repository.items)
}
