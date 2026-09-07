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
    private let historyLimit: Int
    private var transactionStart: [Element]?
    private var transactionChanged = false

    public init(items: [Element] = [], historyLimit: Int = 100) {
        self.items = items
        self.undoItems = []
        self.redoItems = []
        self.historyLimit = max(1, historyLimit)
        self.transactionStart = nil
    }

    public var canUndo: Bool { !undoItems.isEmpty }
    public var canRedo: Bool { !redoItems.isEmpty }

    /// Coalesces a continuous interaction (for example, a slider drag) into
    /// one undo step while keeping each intermediate value in `items`.
    public mutating func beginTransaction() {
        guard transactionStart == nil else { return }
        transactionStart = items
        transactionChanged = false
    }

    public mutating func endTransaction() {
        guard let previous = transactionStart else { return }
        transactionStart = nil
        guard transactionChanged else { return }
        undoItems.append(previous)
        trimHistory(&undoItems)
        redoItems.removeAll()
        transactionChanged = false
    }

    public mutating func append(_ item: Element) {
        recordMutation()
        items.append(item)
    }

    public mutating func replace(at index: Int, with item: Element) {
        guard items.indices.contains(index) else { return }
        recordMutation()
        items[index] = item
    }

    public mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        recordMutation()
        items.remove(at: index)
    }

    public mutating func undo() {
        endTransaction()
        guard let previous = undoItems.popLast() else { return }
        redoItems.append(items)
        trimHistory(&redoItems)
        items = previous
    }

    public mutating func redo() {
        guard let next = redoItems.popLast() else { return }
        undoItems.append(items)
        trimHistory(&undoItems)
        items = next
    }

    private mutating func recordMutation() {
        if transactionStart != nil {
            transactionChanged = true
        } else {
            undoItems.append(items)
            trimHistory(&undoItems)
            redoItems.removeAll()
        }
    }

    private func trimHistory(_ history: inout [[Element]]) {
        let excess = history.count - historyLimit
        guard excess > 0 else { return }
        history.removeFirst(excess)
    }
}
