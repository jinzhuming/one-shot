import AppKit

enum EditorOutputAction { case copy, save, pin, ocr }

@MainActor
struct EditorOutputResult {
    let image: NSImage
    var url: URL?
    var text: String?
}

/// One render pipeline for all output actions, with injectable system work.
@MainActor
struct EditorOutputService {
    var recognizer: any TextRecognizing = VisionTextRecognizer()
    var render: (AnnotationRenderSnapshot) async throws -> CGImage = { snapshot in
        try await BackgroundWork.run {
            guard let image = snapshot.renderedCGImage() else { throw ImageExporter.ExportError.encodingFailed }
            return image
        }
    }
    var save: (NSImage, SaveFormat, ImageExportDestination) async throws -> URL = { image, format, destination in
        try await ImageExporter.save(image, format: format, destination: destination)
    }

    func perform(
        _ action: EditorOutputAction,
        snapshot: AnnotationRenderSnapshot,
        format: SaveFormat,
        destination: ImageExportDestination?
    ) async throws -> EditorOutputResult {
        try Task.checkCancellation()
        let cgImage = try await render(snapshot)
        try Task.checkCancellation()
        let image = NSImage(cgImage: cgImage, size: snapshot.size)
        var result = EditorOutputResult(image: image)
        switch action {
        case .save:
            guard let destination else { throw ImageExporter.ExportError.encodingFailed }
            result.url = try await save(image, format, destination)
        case .ocr:
            result.text = try await recognizer.recognize(cgImage)
        case .copy, .pin:
            break
        }
        try Task.checkCancellation()
        return result
    }
}
