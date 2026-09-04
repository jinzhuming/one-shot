import AppKit
import ShotKit

enum AnnotationToolID: String, CaseIterable, Identifiable {
    case arrow, rect, ellipse, line, pen, highlighter, text, counter, mosaic, spotlight

    var id: String { rawValue }

    private struct Metadata {
        let title: String.LocalizationValue
        let helpText: String.LocalizationValue
        let shortcut: String
        let keyCode: UInt16
    }

    private var metadata: Metadata {
        switch self {
        case .arrow:
            return Metadata(title: "箭头", helpText: "使用箭头标注（1）", shortcut: "1", keyCode: 18)
        case .rect:
            return Metadata(title: "矩形", helpText: "绘制矩形框（2）", shortcut: "2", keyCode: 19)
        case .ellipse:
            return Metadata(title: "椭圆", helpText: "绘制椭圆框（3）", shortcut: "3", keyCode: 20)
        case .line:
            return Metadata(title: "直线", helpText: "绘制直线（4）", shortcut: "4", keyCode: 21)
        case .pen:
            return Metadata(title: "画笔", helpText: "自由绘制（5）", shortcut: "5", keyCode: 23)
        case .highlighter:
            return Metadata(title: "荧光笔", helpText: "使用半透明宽线标记（6）", shortcut: "6", keyCode: 22)
        case .text:
            return Metadata(title: "文字", helpText: "添加文字（7）", shortcut: "7", keyCode: 26)
        case .counter:
            return Metadata(title: "序号", helpText: "添加序号标记（8）", shortcut: "8", keyCode: 28)
        case .mosaic:
            return Metadata(title: "马赛克", helpText: "遮挡指定区域（9）", shortcut: "9", keyCode: 25)
        case .spotlight:
            return Metadata(title: "聚光", helpText: "突出指定区域（0）", shortcut: "0", keyCode: 29)
        }
    }

    var title: String { String(localized: metadata.title) }

    var helpText: String { String(localized: metadata.helpText) }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "minus"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .mosaic: return "square.grid.3x3.fill"
        case .spotlight: return "sun.max"
        }
    }

    var shortcut: String { metadata.shortcut }

    var shortcutKeyCode: UInt16 { metadata.keyCode }

    /// The toolbar order is kept explicit so every implemented tool, including
    /// mosaic, remains visible even when the enum gains another tool later.
    static let groups: [[AnnotationToolID]] = [
        [.arrow, .rect, .ellipse, .line],
        [.pen, .highlighter],
        [.text, .counter],
        [.mosaic, .spotlight]
    ]

    static func fromShortcutKeyCode(_ keyCode: UInt16) -> AnnotationToolID? {
        allCases.first { $0.shortcutKeyCode == keyCode }
    }
}

enum CanvasEvent {
    case down(CGPoint, shift: Bool)
    case drag(CGPoint, shift: Bool)
    case up(CGPoint, shift: Bool)

    var point: CGPoint {
        switch self {
        case .down(let point, _), .drag(let point, _), .up(let point, _):
            return point
        }
    }

    var shift: Bool {
        switch self {
        case .down(_, let shift), .drag(_, let shift), .up(_, let shift):
            return shift
        }
    }
}

protocol AnnotationTool {
    var id: AnnotationToolID { get }
    func handle(_ event: CanvasEvent, document: inout AnnotationDocument)
}

enum AnnotationTools {
    static func tool(for id: AnnotationToolID) -> AnnotationTool {
        switch id {
        case .arrow: return ShapeTool(id: .arrow)
        case .rect: return ShapeTool(id: .rect)
        case .ellipse: return ShapeTool(id: .ellipse)
        case .line: return ShapeTool(id: .line)
        case .pen: return PathTool(id: .pen)
        case .highlighter: return PathTool(id: .highlighter)
        case .text: return TextPlaceholderTool()
        case .counter: return CounterTool()
        case .mosaic: return ShapeTool(id: .mosaic)
        case .spotlight: return ShapeTool(id: .spotlight)
        }
    }
}

struct ShapeTool: AnnotationTool {
    let id: AnnotationToolID

    func handle(_ event: CanvasEvent, document: inout AnnotationDocument) {
        switch event {
        case .down(let point, _):
            document.gestureStart = point
            document.draft = nil
        case .drag(let point, let shift):
            guard let start = document.gestureStart else { return }
            document.draft = makeElement(from: start, to: point, style: document.style, shift: shift)
        case .up(let point, let shift):
            guard let start = document.gestureStart else { return }
            if let element = makeElement(from: start, to: point, style: document.style, shift: shift),
               isSignificant(element) {
                document.commit(element)
            } else {
                document.draft = nil
                document.gestureStart = nil
            }
        }
    }

    private func makeElement(
        from start: CGPoint,
        to end: CGPoint,
        style: AnnotationStyle,
        shift: Bool
    ) -> AnnotationElement? {
        let snapped = shift ? AnnotationMath.snappedEndpoint(from: start, to: end) : end
        let rect = SelectionGeometry.rect(from: start, to: end, square: shift)
        switch id {
        case .arrow:
            return .arrow(start: start, end: snapped, style: style)
        case .rect:
            return .rect(rect, style: style)
        case .ellipse:
            return .ellipse(rect, style: style)
        case .line:
            return .line(start: start, end: snapped, style: style)
        case .mosaic:
            return .mosaic(rect, blockSize: style.mosaicBlockSize)
        case .spotlight:
            return .spotlight(rect, opacity: style.spotlightOpacity)
        default:
            return nil
        }
    }

    private func isSignificant(_ element: AnnotationElement) -> Bool {
        switch element {
        case .arrow(let start, let end, _), .line(let start, let end, _):
            return AnnotationMath.isSignificantDistance(start, end)
        case .rect(let rect, _), .ellipse(let rect, _), .mosaic(let rect, _), .spotlight(let rect, _):
            return AnnotationMath.isSignificantRect(rect)
        default:
            return true
        }
    }
}

struct PathTool: AnnotationTool {
    let id: AnnotationToolID

    func handle(_ event: CanvasEvent, document: inout AnnotationDocument) {
        switch event {
        case .down(let point, _):
            document.penPoints = [point]
            document.draft = make(document.penPoints, style: document.style)
        case .drag(let point, _):
            document.penPoints.append(point)
            document.draft = make(document.penPoints, style: document.style)
        case .up(let point, _):
            document.penPoints.append(point)
            let points = document.penPoints
            if points.count >= 2 {
                if let element = make(points, style: document.style) {
                    document.commit(element)
                }
            } else {
                document.draft = nil
                document.penPoints = []
            }
        }
    }

    private func make(_ points: [CGPoint], style: AnnotationStyle) -> AnnotationElement? {
        switch id {
        case .pen:
            return .pen(points: points, style: style)
        case .highlighter:
            return .highlighter(points: points, style: style)
        default:
            return nil
        }
    }
}

struct TextPlaceholderTool: AnnotationTool {
    let id: AnnotationToolID = .text
    func handle(_ event: CanvasEvent, document: inout AnnotationDocument) {
        _ = event
        _ = document
    }
}

struct CounterTool: AnnotationTool {
    let id: AnnotationToolID = .counter

    func handle(_ event: CanvasEvent, document: inout AnnotationDocument) {
        guard case .up(let point, _) = event else { return }
        let next = AnnotationMath.nextCounter(existing: document.elements.compactMap(\.counterValue))
        document.commit(.counter(next, center: point, style: document.style))
    }
}
