import AppKit
import SwiftUI

@MainActor
final class EditSession: ObservableObject {
    @Published var document: AnnotationDocument
    @Published var selectedTool: AnnotationToolID = .pen {
        didSet { loadPreferencesForSelectedTool() }
    }
    @Published var color: Color
    @Published var lineWidth: Double {
        didSet {
            guard !isLoadingPreferences else { return }
            updatePreferences { $0.setLineWidth(lineWidth, for: selectedTool) }
        }
    }
    @Published var highlighterOpacity: Double {
        didSet {
            guard !isLoadingPreferences, selectedTool == .highlighter else { return }
            updatePreferences { $0.highlighterOpacity = highlighterOpacity }
        }
    }
    @Published var mosaicBlockSize: Double {
        didSet {
            guard !isLoadingPreferences, selectedTool == .mosaic else { return }
            updatePreferences { $0.mosaicBlockSize = mosaicBlockSize }
        }
    }
    @Published var spotlightOpacity: Double {
        didSet {
            guard !isLoadingPreferences, selectedTool == .spotlight else { return }
            updatePreferences { $0.spotlightOpacity = spotlightOpacity }
        }
    }
    @Published var textEditOrigin: CGPoint?
    @Published private(set) var isExporting = false

    private let settings: AppSettings
    private var isLoadingPreferences = false

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }
    var isEditingText: Bool { textEditOrigin != nil }

    convenience init(image: NSImage) {
        self.init(image: image, settings: AppSettings.shared)
    }

    init(image: NSImage, settings: AppSettings) {
        self.settings = settings
        let style = AnnotationStyle()
        document = AnnotationDocument(baseImage: image, style: style)
        color = Color(nsColor: style.color)
        let preferences = settings.annotationPreferences
        lineWidth = preferences.lineWidth(for: .pen)
        highlighterOpacity = preferences.highlighterOpacity
        mosaicBlockSize = preferences.mosaicBlockSize
        spotlightOpacity = preferences.spotlightOpacity
    }

    func handle(_ event: CanvasEvent) {
        applyStyle()
        if selectedTool == .text {
            return
        }
        AnnotationTools.tool(for: selectedTool).handle(event, document: &document)
        objectWillChange.send()
    }

    func beginText(at point: CGPoint) {
        applyStyle()
        textEditOrigin = point
        objectWillChange.send()
    }

    func commitText(_ string: String, at point: CGPoint) {
        applyStyle()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        textEditOrigin = nil
        guard !trimmed.isEmpty else {
            objectWillChange.send()
            return
        }
        document.commit(.text(trimmed, origin: point, style: document.style))
        objectWillChange.send()
    }

    func cancelTextEditing() -> Bool {
        guard textEditOrigin != nil else { return false }
        textEditOrigin = nil
        objectWillChange.send()
        return true
    }

    func undo() {
        guard document.canUndo else { return }
        textEditOrigin = nil
        document.undo()
        objectWillChange.send()
    }

    func redo() {
        guard document.canRedo else { return }
        textEditOrigin = nil
        document.redo()
        objectWillChange.send()
    }

    func beginExport() -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        return true
    }

    func endExport() {
        isExporting = false
    }

    private func applyStyle() {
        document.style.color = NSColor(color)
        document.style.lineWidth = CGFloat(lineWidth)
        document.style.highlighterOpacity = CGFloat(highlighterOpacity)
        document.style.mosaicBlockSize = CGFloat(mosaicBlockSize)
        document.style.spotlightOpacity = CGFloat(spotlightOpacity)
    }

    private func loadPreferencesForSelectedTool() {
        let preferences = settings.annotationPreferences
        isLoadingPreferences = true
        lineWidth = preferences.lineWidth(for: selectedTool)
        switch selectedTool {
        case .highlighter:
            highlighterOpacity = preferences.highlighterOpacity
        case .mosaic:
            mosaicBlockSize = preferences.mosaicBlockSize
        case .spotlight:
            spotlightOpacity = preferences.spotlightOpacity
        default:
            break
        }
        isLoadingPreferences = false
    }

    private func updatePreferences(_ update: (inout AnnotationPreferences) -> Void) {
        var preferences = settings.annotationPreferences
        update(&preferences)
        settings.annotationPreferences = preferences.validated()
    }
}
