import AppKit
import ImageIO
import ShotKit
import UniformTypeIdentifiers

@MainActor
enum ImageExporter {
    static func defaultFilename(format: SaveFormat, date: Date = Date()) -> String {
        ExportNaming.filename(fileExtension: format.fileExtension, date: date)
    }

    static func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func save(_ image: NSImage, format: SaveFormat, to url: URL) async throws {
        guard let cgImage = cgImage(from: image) else {
            throw ExportError.encodingFailed
        }

        let typeIdentifier = format.utTypeIdentifier
        let quality = format == .jpeg ? 0.9 : 1.0
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            encodedImageData(
                cgImage,
                typeIdentifier: typeIdentifier,
                quality: quality
            )
        }).value else {
            throw ExportError.encodingFailed
        }

        try await Task.detached(priority: .utility, operation: {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }).value
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

    static func destinationURL(settings: AppSettings) -> URL? {
        if settings.askWhereToSave {
            return promptSaveURL(format: settings.saveFormat, directory: settings.saveDirectoryURL)
        }
        let directory = settings.saveDirectoryURL
        return directory.appendingPathComponent(defaultFilename(format: settings.saveFormat))
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

        var errorDescription: String? {
            String(localized: "无法编码截图。")
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
