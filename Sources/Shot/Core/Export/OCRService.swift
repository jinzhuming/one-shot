import AppKit
import ShotKit
import Vision

enum OCRService {
    static func recognizeText(in image: NSImage) async -> String {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return ""
        }
        let lines = await Task.detached(priority: .userInitiated) {
            recognizedLines(in: cgImage)
        }.value
        return joined(lines)
    }

    static func joined(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func recognizedLines(in cgImage: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
