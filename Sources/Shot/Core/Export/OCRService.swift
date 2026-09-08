import AppKit
import Vision

@MainActor
protocol TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String
}

struct VisionTextRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String {
        let request = RecognitionRequest()
        return try await withTaskCancellationHandler {
            try await BackgroundWork.run {
                try request.perform(image)
            }
        } onCancel: {
            request.cancel()
        }
    }
}

/// Vision supports cancellation from another thread. The request is configured
/// once, then used exclusively by the worker except for cancel().
private final class RecognitionRequest: @unchecked Sendable {
    private let request = VNRecognizeTextRequest()

    init() {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    }

    func cancel() { request.cancel() }

    func perform(_ image: CGImage) throws -> String {
        try Task.checkCancellation()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            try Task.checkCancellation()
            throw OCRService.RecognitionError.failed
        }
        try Task.checkCancellation()
        return OCRService.joined((request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        })
    }
}

enum OCRService {
    @MainActor
    static func recognizeText(
        in image: NSImage,
        recognizer: (any TextRecognizing)? = nil
    ) async throws -> String {
        guard let cgImage = ImageExporter.cgImage(from: image) else {
            throw RecognitionError.invalidImage
        }
        let interval = Diagnostics.performance.beginInterval("Text recognition")
        defer { Diagnostics.performance.endInterval("Text recognition", interval) }
        let text = try await (recognizer ?? VisionTextRecognizer()).recognize(cgImage)
        try Task.checkCancellation()
        return text
    }

    static func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    enum RecognitionError: LocalizedError {
        case invalidImage
        case failed

        var errorDescription: String? {
            switch self {
            case .invalidImage: return String(localized: "无法读取用于识别文字的截图。")
            case .failed: return String(localized: "文字识别失败，请重试。")
            }
        }
    }
}
