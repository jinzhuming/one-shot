import AppKit
import ShotKit

struct AnnotationStyle {
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var highlighterOpacity: CGFloat = 0.4
    var mosaicBlockSize: CGFloat = 10
    var spotlightOpacity: CGFloat = 0.5

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
        case .arrow, .rect, .ellipse, .line:
            return shapeLineWidth
        case .pen:
            return penLineWidth
        case .highlighter:
            return highlighterLineWidth
        case .text:
            return textLineWidth
        case .counter:
            return counterLineWidth
        case .mosaic, .spotlight:
            return shapeLineWidth
        }
    }

    mutating func setLineWidth(_ value: Double, for tool: AnnotationToolID) {
        switch tool {
        case .arrow, .rect, .ellipse, .line, .mosaic, .spotlight:
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
}

struct AnnotationDocument {
    var baseImage: NSImage
    var style: AnnotationStyle
    var stack: UndoStack<AnnotationElement>
    var draft: AnnotationElement?
    var gestureStart: CGPoint?
    var penPoints: [CGPoint] = []

    init(baseImage: NSImage, style: AnnotationStyle = AnnotationStyle()) {
        self.baseImage = baseImage
        self.style = style
        self.stack = UndoStack()
    }

    var elements: [AnnotationElement] { stack.items }
    var visibleElements: [AnnotationElement] {
        guard let draft else { return elements }
        return elements + [draft]
    }
    var canUndo: Bool { stack.canUndo }
    var canRedo: Bool { stack.canRedo }

    mutating func commit(_ element: AnnotationElement) {
        stack.append(element)
        draft = nil
        gestureStart = nil
        penPoints = []
    }

    mutating func undo() {
        draft = nil
        gestureStart = nil
        penPoints = []
        stack.undo()
    }

    mutating func redo() {
        draft = nil
        gestureStart = nil
        penPoints = []
        stack.redo()
    }

    func flattened(includeDraft: Bool = false) -> NSImage {
        guard let output = flattenedCGImage(includeDraft: includeDraft) else {
            return baseImage
        }
        return NSImage(cgImage: output, size: baseImage.size)
    }

    func flattenedCGImage(includeDraft: Bool = false) -> CGImage? {
        let size = baseImage.size
        var proposed = CGRect(origin: .zero, size: size)
        guard let baseCG = baseImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        let width = baseCG.width
        let height = baseCG.height
        let colorSpace = baseCG.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        // Bitmap is CG-native (origin bottom-left). Annotations match the flipped
        // canvas: origin top-left, y down. Draw the screenshot in pixel space first,
        // then flip once for shapes/text so they land on the same pixels the mouse maps to.
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) / max(size.width, 1), y: -CGFloat(height) / max(size.height, 1))
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        var toDraw = elements
        if includeDraft, let draft {
            toDraw.append(draft)
        }
        AnnotationRenderer.draw(toDraw, baseImage: baseImage, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}

/// Immutable value snapshot used to move expensive rendering off the main actor.
/// The document is never mutated after this wrapper is created.
struct AnnotationRenderSnapshot: @unchecked Sendable {
    let document: AnnotationDocument

    init(document: AnnotationDocument) {
        self.document = document
    }

    func renderedCGImage() -> CGImage? {
        document.flattenedCGImage(includeDraft: true)
    }
}
