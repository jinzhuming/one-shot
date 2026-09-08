import AppKit
import ImageIO
import ShotKit
import UniformTypeIdentifiers

@MainActor
enum ImageExporter {
    static func defaultFilename(format: SaveFormat, date: Date = Date()) -> String {
        ExportNaming.filename(fileExtension: format.fileExtension, date: date)
    }

    @discardableResult
    static func copyToClipboard(_ image: NSImage) -> Bool {
        guard cgImage(from: image) != nil else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Do not clear a second time on failure. Some pasteboard providers can
        // fail after declaring their types; a second clear only makes recovery
        // worse and cannot improve the result.
        return pasteboard.writeObjects([image])
    }

    @discardableResult
    static func save(_ image: NSImage, format: SaveFormat, to url: URL) async throws -> URL {
        try await save(image, format: format, destination: .chosen(url))
    }

    static func save(
        _ image: NSImage,
        format: SaveFormat,
        destination: ImageExportDestination
    ) async throws -> URL {
        guard let cgImage = cgImage(from: image) else { throw ExportError.encodingFailed }
        let identifier = format.utTypeIdentifier
        let quality = format == .jpeg ? 0.9 : 1.0
        let interval = Diagnostics.performance.beginInterval("Image export")
        defer { Diagnostics.performance.endInterval("Image export", interval) }
        return try await BackgroundWork.run {
            guard let data = encodedImageData(cgImage, typeIdentifier: identifier, quality: quality) else {
                throw ExportError.encodingFailed
            }
            try Task.checkCancellation()
            return try AtomicFileWriter.write(data, to: destination)
        }
    }

    static func promptSaveURL(format: SaveFormat, directory: URL) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [utType(for: format)]
        panel.directoryURL = directory
        panel.nameFieldStringValue = defaultFilename(format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func destination(settings: AppSettings) -> ImageExportDestination? {
        if settings.askWhereToSave {
            return promptSaveURL(format: settings.saveFormat, directory: settings.saveDirectoryURL).map {
                .chosen($0)
            }
        }
        return .automatic(
            directory: settings.saveDirectoryURL,
            filename: defaultFilename(format: settings.saveFormat)
        )
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func utType(for format: SaveFormat) -> UTType {
        switch format {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    enum ExportError: LocalizedError {
        case encodingFailed
        case clipboardFailed
        case savedButClipboardFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return String(localized: "无法编码截图。")
            case .savedButClipboardFailed:
                return String(localized: "截图已保存，但无法复制到剪贴板。")
            case .clipboardFailed:
                return String(localized: "无法复制截图到剪贴板。")
            }
        }
    }
}

private func encodedImageData(
    _ image: CGImage,
    typeIdentifier: String,
    quality: Double
) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        typeIdentifier as CFString,
        1,
        nil
    ) else { return nil }
    var properties: [CFString: Any] = [:]
    if quality < 1 {
        properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
