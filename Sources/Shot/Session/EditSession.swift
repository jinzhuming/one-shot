import AppKit
import SwiftUI

@MainActor
final class EditSession: ObservableObject {
    @Published var document: AnnotationDocument
    @Published var selectedTool: AnnotationToolID = .pen {
        didSet { loadPreferencesForSelectedTool() }
    }
    @Published var color: Color {
        didSet {
            guard !isLoadingPreferences else { return }
            document.style.color = NSColor(color)
            if selectedTool == .select, document.selectedObject != nil {
                document.updateSelected { $0.withColor(NSColor(color)) }
                objectWillChange.send()
            }
        }
    }
    @Published var lineWidth: Double {
        didSet {
            guard !isLoadingPreferences else { return }
            if selectedTool == .select, document.selectedObject != nil {
                document.updateSelected { $0.withLineWidth(CGFloat(lineWidth)) }
                objectWillChange.send()
                return
            }
            updatePreferences { $0.setLineWidth(lineWidth, for: selectedTool) }
        }
    }
    @Published var highlighterOpacity: Double {
        didSet {
            guard !isLoadingPreferences else { return }
            if selectedTool == .select, document.selectedObject != nil {
                document.updateSelected { $0.withHighlighterOpacity(CGFloat(highlighterOpacity)) }
                objectWillChange.send()
                return
            }
            guard selectedTool == .highlighter else { return }
            updatePreferences { $0.highlighterOpacity = highlighterOpacity }
        }
    }
    @Published var mosaicBlockSize: Double {
        didSet {
            guard !isLoadingPreferences else { return }
            if selectedTool == .select, document.selectedObject != nil {
                document.updateSelected { $0.withMosaicBlockSize(CGFloat(mosaicBlockSize)) }
                objectWillChange.send()
                return
            }
            guard selectedTool == .mosaic else { return }
            updatePreferences { $0.mosaicBlockSize = mosaicBlockSize }
        }
    }
    @Published var spotlightOpacity: Double {
        didSet {
            guard !isLoadingPreferences else { return }
            if selectedTool == .select, document.selectedObject != nil {
                document.updateSelected { $0.withSpotlightOpacity(CGFloat(spotlightOpacity)) }
                objectWillChange.send()
                return
            }
            guard selectedTool == .spotlight else { return }
            updatePreferences { $0.spotlightOpacity = spotlightOpacity }
        }
    }
    @Published var textEditOrigin: CGPoint?
    @Published private(set) var textEditID: UUID?
    @Published private(set) var isExporting = false

    private let settings: AppSettings
    private var isLoadingPreferences = false

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }
    var isEditingText: Bool { textEditOrigin != nil }
    var hasSelection: Bool { document.selectedObject != nil }

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
        if selectedTool == .select, case .up = event {
            loadAppearanceFromSelection()
        }
        objectWillChange.send()
    }

    func beginText(at point: CGPoint, replacing id: UUID? = nil) {
        applyStyle()
        textEditOrigin = point
        textEditID = id
        objectWillChange.send()
    }

    func commitText(_ string: String, at point: CGPoint, replacing id: UUID? = nil) {
        applyStyle()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        textEditOrigin = nil
        textEditID = nil
        guard !trimmed.isEmpty else {
            objectWillChange.send()
            return
        }
        if let id {
            document.replaceText(id: id, with: trimmed)
        } else {
            document.commit(.text(trimmed, origin: point, style: document.style))
        }
        objectWillChange.send()
    }

    func cancelTextEditing() -> Bool {
        guard textEditOrigin != nil else { return false }
        textEditOrigin = nil
        textEditID = nil
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

    func deleteSelection() {
        guard selectedTool == .select else { return }
        document.removeSelected()
        objectWillChange.send()
    }

    func duplicateSelection() {
        guard selectedTool == .select else { return }
        document.duplicateSelected()
        loadAppearanceFromSelection()
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

    func beginStyleAdjustment() {
        guard selectedTool == .select, document.selectedObject != nil else { return }
        document.beginUndoTransaction()
    }

    func endStyleAdjustment() {
        document.endUndoTransaction()
        objectWillChange.send()
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

    private func loadAppearanceFromSelection() {
        guard let selected = document.selectedObject else { return }
        isLoadingPreferences = true
        if let style = selected.style {
            color = Color(nsColor: style.color)
            lineWidth = Double(style.lineWidth)
            highlighterOpacity = Double(style.highlighterOpacity)
        }
        switch selected.element {
        case .mosaic(_, let blockSize): mosaicBlockSize = Double(blockSize)
        case .spotlight(_, let opacity): spotlightOpacity = Double(opacity)
        default: break
        }
        isLoadingPreferences = false
    }

    private func updatePreferences(_ update: (inout AnnotationPreferences) -> Void) {
        var preferences = settings.annotationPreferences
        update(&preferences)
        settings.annotationPreferences = preferences.validated()
    }
}
