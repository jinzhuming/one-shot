import CoreGraphics

public enum AnnotationMath {
    public static func nextCounter(existing: [Int]) -> Int {
        (existing.max() ?? 0) + 1
    }

    public static func isSignificantRect(_ rect: CGRect, minSize: CGFloat = 3) -> Bool {
        rect.width >= minSize && rect.height >= minSize
    }

    public static func isSignificantDistance(_ a: CGPoint, _ b: CGPoint, minimum: CGFloat = 3) -> Bool {
        hypot(b.x - a.x, b.y - a.y) >= minimum
    }

    /// Snaps `end` onto the nearest 45° ray from `start`, keeping distance.
    public static func snappedEndpoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return end }
        let step = CGFloat.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(
            x: start.x + distance * cos(snapped),
            y: start.y + distance * sin(snapped)
        )
    }

    public static func fontSize(lineWidth: CGFloat) -> CGFloat {
        max(24, 16 + lineWidth * 4)
    }

    public static let strokePresets: [CGFloat] = [2, 4, 8]
}

public struct UndoStack<Element> {
    public private(set) var items: [Element]
    private var undoItems: [[Element]]
    private var redoItems: [[Element]]

    public init(items: [Element] = []) {
        self.items = items
        self.undoItems = []
        self.redoItems = []
    }

    public var canUndo: Bool { !undoItems.isEmpty }
    public var canRedo: Bool { !redoItems.isEmpty }

    public mutating func append(_ item: Element) {
        undoItems.append(items)
        redoItems.removeAll()
        items.append(item)
    }

    public mutating func undo() {
        guard let previous = undoItems.popLast() else { return }
        redoItems.append(items)
        items = previous
    }

    public mutating func redo() {
        guard let next = redoItems.popLast() else { return }
        undoItems.append(items)
        items = next
    }
}
