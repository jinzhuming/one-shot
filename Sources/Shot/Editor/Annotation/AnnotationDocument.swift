import AppKit
import ShotKit

struct AnnotationStyle {
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var highlighterOpacity: CGFloat = 0.4
    var mosaicBlockSize: CGFloat = 10
    var spotlightOpacity: CGFloat = 0.5
    var textScale: CGFloat = 1
    var counterScale: CGFloat = 1

    static let minimumAnnotationScale: CGFloat = 0.25
    static let maximumAnnotationScale: CGFloat = 4

    func applying(color: NSColor, lineWidth: CGFloat) -> AnnotationStyle {
        var copy = self
        copy.color = color
        copy.lineWidth = lineWidth
        return copy
    }
}

struct AnnotationPreferences: Codable, Equatable {
    var shapeLineWidth: Double = 4
    var penLineWidth: Double = 4
    var highlighterLineWidth: Double = 4
    var highlighterOpacity: Double = 0.4
    var textLineWidth: Double = 4
    var counterLineWidth: Double = 4
    var mosaicBlockSize: Double = 10
    var spotlightOpacity: Double = 0.5

    static let `default` = AnnotationPreferences()

    func validated() -> AnnotationPreferences {
        var copy = self
        copy.shapeLineWidth = Self.clamped(copy.shapeLineWidth, lower: 1, upper: 24, fallback: 4)
        copy.penLineWidth = Self.clamped(copy.penLineWidth, lower: 1, upper: 24, fallback: 4)
        copy.highlighterLineWidth = Self.clamped(copy.highlighterLineWidth, lower: 1, upper: 32, fallback: 4)
        copy.highlighterOpacity = Self.clamped(copy.highlighterOpacity, lower: 0.1, upper: 1, fallback: 0.4)
        copy.textLineWidth = Self.clamped(copy.textLineWidth, lower: 1, upper: 12, fallback: 4)
        copy.counterLineWidth = Self.clamped(copy.counterLineWidth, lower: 1, upper: 12, fallback: 4)
        copy.mosaicBlockSize = Self.clamped(copy.mosaicBlockSize, lower: 2, upper: 32, fallback: 10)
        copy.spotlightOpacity = Self.clamped(copy.spotlightOpacity, lower: 0.1, upper: 0.9, fallback: 0.5)
        return copy
    }

    func lineWidth(for tool: AnnotationToolID) -> Double {
        switch tool {
        case .select, .arrow, .rect, .ellipse, .line, .mosaic, .spotlight:
            return shapeLineWidth
        case .pen:
            return penLineWidth
        case .highlighter:
            return highlighterLineWidth
        case .text:
            return textLineWidth
        case .counter:
            return counterLineWidth
        }
    }

    mutating func setLineWidth(_ value: Double, for tool: AnnotationToolID) {
        switch tool {
        case .select, .arrow, .rect, .ellipse, .line, .mosaic, .spotlight:
            shapeLineWidth = value
        case .pen:
            penLineWidth = value
        case .highlighter:
            highlighterLineWidth = value
        case .text:
            textLineWidth = value
        case .counter:
            counterLineWidth = value
        }
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, lower), upper)
    }
}

enum AnnotationElement {
    case arrow(start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case rect(CGRect, style: AnnotationStyle)
    case ellipse(CGRect, style: AnnotationStyle)
    case line(start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case pen(points: [CGPoint], style: AnnotationStyle)
    case highlighter(points: [CGPoint], style: AnnotationStyle)
    case text(String, origin: CGPoint, style: AnnotationStyle)
    case counter(Int, center: CGPoint, style: AnnotationStyle)
    case mosaic(CGRect, blockSize: CGFloat)
    case spotlight(CGRect, opacity: CGFloat)

    var counterValue: Int? {
        if case .counter(let value, _, _) = self { return value }
        return nil
    }

    var style: AnnotationStyle? {
        switch self {
        case .arrow(_, _, let style), .rect(_, let style), .ellipse(_, let style),
             .line(_, _, let style), .pen(_, let style), .highlighter(_, let style),
             .text(_, _, let style), .counter(_, _, let style):
            return style
        case .mosaic, .spotlight:
            return nil
        }
    }

    func applying(style newStyle: AnnotationStyle) -> AnnotationElement {
        switch self {
        case .arrow(let start, let end, _): return .arrow(start: start, end: end, style: newStyle)
        case .rect(let rect, _): return .rect(rect, style: newStyle)
        case .ellipse(let rect, _): return .ellipse(rect, style: newStyle)
        case .line(let start, let end, _): return .line(start: start, end: end, style: newStyle)
        case .pen(let points, _): return .pen(points: points, style: newStyle)
        case .highlighter(let points, _): return .highlighter(points: points, style: newStyle)
        case .text(let string, let origin, _): return .text(string, origin: origin, style: newStyle)
        case .counter(let value, let center, _): return .counter(value, center: center, style: newStyle)
        case .mosaic(let rect, let blockSize): return .mosaic(rect, blockSize: blockSize)
        case .spotlight(let rect, let opacity): return .spotlight(rect, opacity: opacity)
        }
    }
}

struct AnnotationObject: Identifiable {
    let id: UUID
    var element: AnnotationElement

    init(id: UUID = UUID(), element: AnnotationElement) {
        self.id = id
        self.element = element
    }

    var bounds: CGRect {
        let raw: CGRect
        switch element {
        case .arrow(let start, let end, let style), .line(let start, let end, let style):
            raw = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ).insetBy(dx: -style.lineWidth * 2, dy: -style.lineWidth * 2)
        case .rect(let rect, let style), .ellipse(let rect, let style):
            raw = rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case .pen(let points, let style), .highlighter(let points, let style):
            let padding = style.lineWidth * (isHighlighter ? 2 : 1)
            raw = pointBounds(points).insetBy(dx: -padding, dy: -padding)
        case .text(let string, let origin, let style):
            let font = NSFont.systemFont(
                ofSize: AnnotationMath.fontSize(lineWidth: style.lineWidth)
                    * min(max(style.textScale, AnnotationStyle.minimumAnnotationScale), AnnotationStyle.maximumAnnotationScale),
                weight: .medium
            )
            let size = (string as NSString).size(withAttributes: [.font: font])
            raw = CGRect(origin: origin, size: CGSize(width: max(1, size.width), height: max(1, size.height)))
        case .counter(_, let center, let style):
            let scale = min(max(style.counterScale, AnnotationStyle.minimumAnnotationScale), AnnotationStyle.maximumAnnotationScale)
            let radius = max(10, style.lineWidth * 5 * scale)
            raw = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        case .mosaic(let rect, _), .spotlight(let rect, _):
            raw = rect
        }
        return raw.standardized
    }

    var style: AnnotationStyle? { element.style }
    var counterValue: Int? { element.counterValue }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch element {
        case .arrow(let start, let end, let style), .line(let start, let end, let style):
            return AnnotationGeometry.hitTest(
                point: point,
                shape: .line(start, end),
                tolerance: tolerance + style.lineWidth
            )
        case .rect(let rect, let style):
            return rect.insetBy(dx: -tolerance - style.lineWidth, dy: -tolerance - style.lineWidth).contains(point)
        case .ellipse(let rect, let style):
            return AnnotationGeometry.hitTest(point: point, shape: .filledEllipse(rect), tolerance: tolerance + style.lineWidth)
        case .pen(let points, let style), .highlighter(let points, let style):
            return AnnotationGeometry.hitTest(point: point, shape: .polyline(points), tolerance: tolerance + style.lineWidth)
        case .text, .mosaic, .spotlight:
            return AnnotationGeometry.hitTest(point: point, shape: .filledRect(bounds), tolerance: tolerance)
        case .counter:
            return AnnotationGeometry.hitTest(point: point, shape: .filledEllipse(bounds), tolerance: tolerance)
        }
    }

    func translated(by delta: CGSize, inside canvas: CGRect) -> AnnotationObject {
        let target = AnnotationGeometry.movedRect(bounds, by: delta, inside: canvas)
        let actualDelta = CGSize(width: target.minX - bounds.minX, height: target.minY - bounds.minY)
        return transformed(by: CGAffineTransform(translationX: actualDelta.width, y: actualDelta.height))
    }

    func resized(to newBounds: CGRect) -> AnnotationObject {
        let old = bounds
        let sx = newBounds.width / max(old.width, 0.001)
        let sy = newBounds.height / max(old.height, 0.001)
        let transform = CGAffineTransform(
            a: sx,
            b: 0,
            c: 0,
            d: sy,
            tx: newBounds.minX - old.minX * sx,
            ty: newBounds.minY - old.minY * sy
        )
        return transformed(by: transform)
    }

    func withColor(_ color: NSColor) -> AnnotationObject {
        guard var style else { return self }
        style.color = color
        return AnnotationObject(id: id, element: element.applying(style: style))
    }

    func withLineWidth(_ lineWidth: CGFloat) -> AnnotationObject {
        guard var style else { return self }
        style.lineWidth = lineWidth
        return AnnotationObject(id: id, element: element.applying(style: style))
    }

    func withHighlighterOpacity(_ opacity: CGFloat) -> AnnotationObject {
        guard case .highlighter = element, var style else { return self }
        style.highlighterOpacity = opacity
        return AnnotationObject(id: id, element: element.applying(style: style))
    }

    func withMosaicBlockSize(_ size: CGFloat) -> AnnotationObject {
        guard case .mosaic(let rect, _) = element else { return self }
        return AnnotationObject(id: id, element: .mosaic(rect, blockSize: size))
    }

    func withSpotlightOpacity(_ opacity: CGFloat) -> AnnotationObject {
        guard case .spotlight(let rect, _) = element else { return self }
        return AnnotationObject(id: id, element: .spotlight(rect, opacity: opacity))
    }

    func replacingText(_ string: String) -> AnnotationObject {
        guard case .text(_, let origin, let style) = element else { return self }
        return AnnotationObject(id: id, element: .text(string, origin: origin, style: style))
    }

    private var isHighlighter: Bool {
        if case .highlighter = element { return true }
        return false
    }

    private func transformed(by transform: CGAffineTransform) -> AnnotationObject {
        let next: AnnotationElement
        switch element {
        case .arrow(let start, let end, let style):
            next = .arrow(start: start.applying(transform), end: end.applying(transform), style: style)
        case .rect(let rect, let style):
            next = .rect(rect.applying(transform).standardized, style: style)
        case .ellipse(let rect, let style):
            next = .ellipse(rect.applying(transform).standardized, style: style)
        case .line(let start, let end, let style):
            next = .line(start: start.applying(transform), end: end.applying(transform), style: style)
        case .pen(let points, let style):
            next = .pen(points: points.map { $0.applying(transform) }, style: style)
        case .highlighter(let points, let style):
            next = .highlighter(points: points.map { $0.applying(transform) }, style: style)
        case .text(let string, let origin, var style):
            style.textScale = min(
                max(
                    style.textScale * max(AnnotationStyle.minimumAnnotationScale, (abs(transform.a) + abs(transform.d)) / 2),
                    AnnotationStyle.minimumAnnotationScale
                ),
                AnnotationStyle.maximumAnnotationScale
            )
            next = .text(string, origin: origin.applying(transform), style: style)
        case .counter(let value, let center, var style):
            style.counterScale = min(
                max(
                    style.counterScale * max(AnnotationStyle.minimumAnnotationScale, (abs(transform.a) + abs(transform.d)) / 2),
                    AnnotationStyle.minimumAnnotationScale
                ),
                AnnotationStyle.maximumAnnotationScale
            )
            next = .counter(value, center: center.applying(transform), style: style)
        case .mosaic(let rect, let blockSize):
            next = .mosaic(rect.applying(transform).standardized, blockSize: blockSize)
        case .spotlight(let rect, let opacity):
            next = .spotlight(rect.applying(transform).standardized, opacity: opacity)
        }
        return AnnotationObject(id: id, element: next)
    }

    private func pointBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { result, point in
            result.union(CGRect(origin: point, size: .zero))
        }
    }
}

private enum SelectionInteraction {
    case moving(id: UUID, start: CGPoint, original: AnnotationObject)
    case resizing(id: UUID, start: CGPoint, original: AnnotationObject, handle: AnnotationHandle)

    var original: AnnotationObject {
        switch self {
        case .moving(_, _, let original), .resizing(_, _, let original, _): return original
        }
    }
}

struct AnnotationDocument {
    var baseImage: NSImage
    var style: AnnotationStyle
    var stack: UndoStack<AnnotationObject>
    var draft: AnnotationObject?
    var gestureStart: CGPoint?
    var penPoints: [CGPoint] = []
    private var selectionInteraction: SelectionInteraction?
    private(set) var selectedID: UUID?

    init(baseImage: NSImage, style: AnnotationStyle = AnnotationStyle()) {
        self.baseImage = baseImage
        self.style = style
        self.stack = UndoStack()
    }

    var elements: [AnnotationObject] { stack.items }
    var visibleElements: [AnnotationObject] {
        guard let draft else { return elements }
        guard let index = elements.firstIndex(where: { $0.id == draft.id }) else { return elements + [draft] }
        var copy = elements
        copy[index] = draft
        return copy
    }
    var selectedObject: AnnotationObject? { elements.first { $0.id == selectedID } }
    var canUndo: Bool { stack.canUndo }
    var canRedo: Bool { stack.canRedo }

    mutating func commit(_ element: AnnotationElement) {
        stack.append(AnnotationObject(element: element))
        draft = nil
        gestureStart = nil
        penPoints = []
    }

    mutating func select(_ id: UUID?) {
        selectedID = id
        draft = nil
        selectionInteraction = nil
    }

    mutating func handleSelection(_ event: CanvasEvent) {
        switch event {
        case .down(let point, _):
            draft = nil
            selectionInteraction = nil
            let tolerance: CGFloat = 8
            if let selected = selectedObject,
               let handle = AnnotationGeometry.handle(at: point, in: selected.bounds, tolerance: tolerance) {
                selectionInteraction = .resizing(id: selected.id, start: point, original: selected, handle: handle)
                return
            }
            if let hit = elements.reversed().first(where: { $0.hitTest(point, tolerance: tolerance) }) {
                selectedID = hit.id
                selectionInteraction = .moving(id: hit.id, start: point, original: hit)
            } else {
                selectedID = nil
            }
        case .drag(let point, let shift):
            updateSelectionDraft(at: point, preservingAspectRatio: shift)
        case .up(let point, let shift):
            updateSelectionDraft(at: point, preservingAspectRatio: shift)
            guard let interaction = selectionInteraction, let draft else {
                selectionInteraction = nil
                return
            }
            if draft.bounds != interaction.original.bounds {
                replace(draft)
            } else {
                self.draft = nil
            }
            selectionInteraction = nil
        }
    }

    mutating func removeSelected() {
        guard let selectedID, let index = elements.firstIndex(where: { $0.id == selectedID }) else { return }
        stack.remove(at: index)
        self.selectedID = nil
        draft = nil
    }

    mutating func duplicateSelected() {
        guard let selected = selectedObject else { return }
        let copy = selected.translated(by: CGSize(width: 12, height: 12), inside: imageBounds)
        stack.append(AnnotationObject(element: copy.element))
        selectedID = stack.items.last?.id
    }

    mutating func updateSelected(_ update: (AnnotationObject) -> AnnotationObject) {
        guard let selectedID, let index = elements.firstIndex(where: { $0.id == selectedID }) else { return }
        stack.replace(at: index, with: update(elements[index]))
    }

    mutating func beginUndoTransaction() {
        stack.beginTransaction()
    }

    mutating func endUndoTransaction() {
        stack.endTransaction()
    }

    mutating func replaceText(id: UUID, with string: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        stack.replace(at: index, with: elements[index].replacingText(string))
    }

    mutating func undo() {
        draft = nil
        gestureStart = nil
        penPoints = []
        selectionInteraction = nil
        stack.undo()
        if let selectedID, !elements.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
    }

    mutating func redo() {
        draft = nil
        gestureStart = nil
        penPoints = []
        selectionInteraction = nil
        stack.redo()
    }

    func flattened(includeDraft: Bool = false) -> NSImage {
        guard let output = flattenedCGImage(includeDraft: includeDraft) else { return baseImage }
        return NSImage(cgImage: output, size: baseImage.size)
    }

    func flattenedCGImage(includeDraft: Bool = false) -> CGImage? {
        Self.renderedCGImage(
            baseImage: baseImage,
            elements: includeDraft ? visibleElements : elements
        )
    }

    fileprivate static func renderedCGImage(
        baseImage: NSImage,
        elements: [AnnotationObject]
    ) -> CGImage? {
        let size = baseImage.size
        var proposed = CGRect(origin: .zero, size: size)
        guard let baseCG = baseImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let width = baseCG.width
        let height = baseCG.height
        let colorSpace = baseCG.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / max(size.width, 1), y: -CGFloat(height) / max(size.height, 1))
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        AnnotationRenderer.draw(elements, baseImage: baseImage, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private var imageBounds: CGRect { CGRect(origin: .zero, size: baseImage.size) }

    private mutating func updateSelectionDraft(at point: CGPoint, preservingAspectRatio: Bool) {
        guard let interaction = selectionInteraction else { return }
        let transformed: AnnotationObject
        switch interaction {
        case .moving(_, let start, let original):
            transformed = original.translated(
                by: CGSize(width: point.x - start.x, height: point.y - start.y),
                inside: imageBounds
            )
        case .resizing(_, _, let original, let handle):
            let rect = AnnotationGeometry.resizedRect(
                original.bounds,
                handle: handle,
                to: point,
                preservingAspectRatio: preservingAspectRatio,
                inside: imageBounds
            )
            transformed = original.resized(to: rect)
        }
        draft = transformed
    }

    private mutating func replace(_ object: AnnotationObject) {
        guard let index = elements.firstIndex(where: { $0.id == object.id }) else {
            draft = nil
            return
        }
        stack.replace(at: index, with: object)
        draft = nil
    }
}

@MainActor
struct AnnotationRenderSnapshot {
    let baseImage: NSImage
    let elements: [AnnotationObject]

    init(document: AnnotationDocument) {
        self.baseImage = document.baseImage
        self.elements = document.visibleElements
    }

    func renderedCGImage() -> CGImage? {
        AnnotationDocument.renderedCGImage(baseImage: baseImage, elements: elements)
    }
}
