import AppKit
import AVFoundation
import ShotKit
import UniformTypeIdentifiers

enum VideoExporter {
    static let fileExtension = "mp4"
    private static let segmentMergeTimeout: Duration = .seconds(30)

    /// ScreenCaptureKit writes synchronously enough during startup that the
    /// live recording should not depend on access to the user's protected
    /// folders. The finished file is moved to the configured directory after
    /// the stream has stopped.
    static func temporaryRecordingURL(date: Date = Date()) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotRecordings", isDirectory: true)
        return try temporaryRecordingURL(in: directory, date: date)
    }

    static func temporaryRecordingURL(in directory: URL, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = ExportNaming.filename(fileExtension: fileExtension, date: date)
        // Temporary files can be created by a recording task while an older
        // export is still being finalized. A check-then-return collision
        // loop is not atomic, so use a UUID for this internal-only path.
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString).\(fileExtension)")
    }

    static func recordingURL(in directory: URL, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = ExportNaming.filename(fileExtension: fileExtension, date: date)
        let baseURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let name = baseURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(name) (\(index)).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    static func finalizeRecording(sourceURL: URL, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let destinationURL = try recordingURL(in: directory)
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }.value
    }

    /// Combines the temporary files created around a pause/resume cycle into
    /// one playable MP4. ScreenCaptureKit's recording output has no pause API,
    /// so RecordingService records each active interval as its own segment.
    @MainActor
    static func mergeRecordingSegments(
        _ sourceURLs: [URL],
        temporaryDirectory: URL? = nil
    ) async throws -> URL {
        let exportBox = ExportSessionBox()
        return try await AsyncTimeout.run(
            timeout: segmentMergeTimeout,
            timeoutError: ExportError.segmentMergeTimedOut,
            onTimeout: { exportBox.session?.cancelExport() }
        ) {
            try await mergeRecordingSegmentsOperation(
                sourceURLs,
                exportBox: exportBox,
                temporaryDirectory: temporaryDirectory
            )
        }
    }

    @MainActor
    private static func mergeRecordingSegmentsOperation(
        _ sourceURLs: [URL],
        exportBox: ExportSessionBox,
        temporaryDirectory: URL?
    ) async throws -> URL {
        guard !sourceURLs.isEmpty else { throw ExportError.noRecordingSegments }
        guard sourceURLs.count > 1 else { return sourceURLs[0] }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.segmentMergeFailed
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertionTime = CMTime.zero
        for sourceURL in sourceURLs {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: sourceURL)
            guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExportError.segmentMergeFailed
            }
            let duration = try await asset.load(.duration)
            try Task.checkCancellation()
            guard duration.isNumeric, duration > .zero else {
                throw ExportError.segmentMergeFailed
            }
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceVideoTrack,
                at: insertionTime
            )

            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceAudioTrack,
                    at: insertionTime
                )
            }
            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        let mergedURL = try temporaryDirectory.map {
            try temporaryRecordingURL(in: $0)
        } ?? temporaryRecordingURL()
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ExportError.segmentMergeFailed
        }
        exportBox.session = exporter
        do {
            try await exporter.export(to: mergedURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: mergedURL)
            throw error
        }
        exportBox.session = nil
        return mergedURL
    }

    @MainActor
    static func promptSaveURL(sourceURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    @discardableResult
    static func copyToClipboard(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }

    static func copy(_ sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw ExportError.destinationExists
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }

    enum ExportError: LocalizedError {
        case destinationExists
        case clipboardFailed
        case noRecordingSegments
        case segmentMergeFailed
        case segmentMergeTimedOut

        var errorDescription: String? {
            switch self {
            case .destinationExists:
                return String(localized: "目标文件已存在，请选择其他位置。")
            case .clipboardFailed:
                return String(localized: "无法复制视频文件到剪贴板。")
            case .noRecordingSegments, .segmentMergeFailed:
                return String(localized: "录屏片段合并失败。")
            case .segmentMergeTimedOut:
                return String(localized: "录屏片段合并超时，已自动取消。")
            }
        }
    }
}

@MainActor
private final class ExportSessionBox {
    var session: AVAssetExportSession?
}
