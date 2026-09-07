import AppKit
import AVFoundation
import ShotKit
import UniformTypeIdentifiers

@MainActor
enum VideoExporter {
    static let fileExtension = "mp4"

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

    static func promptSaveURL(sourceURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

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

        var errorDescription: String? {
            switch self {
            case .destinationExists:
                return String(localized: "目标文件已存在，请选择其他位置。")
            case .clipboardFailed:
                return String(localized: "无法复制视频文件到剪贴板。")
            }
        }
    }
}
