import CoreGraphics

public enum SelectionGeometry {
    public static func rect(from start: CGPoint, to current: CGPoint, square: Bool) -> CGRect {
        var end = current
        if square {
            let dx = current.x - start.x
            let dy = current.y - start.y
            let size = max(abs(dx), abs(dy))
            end = CGPoint(
                x: start.x + size * (dx < 0 ? -1 : 1),
                y: start.y + size * (dy < 0 ? -1 : 1)
            )
        }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public static func translated(_ rect: CGRect, by delta: CGSize) -> CGRect {
        rect.offsetBy(dx: delta.width, dy: delta.height)
    }

    /// Opposite corner from the mouse, used to resume resize after Space-move.
    public static func resizeAnchor(for rect: CGRect, mouse: CGPoint) -> CGPoint {
        let closerToMinX = abs(mouse.x - rect.minX) <= abs(mouse.x - rect.maxX)
        let closerToMinY = abs(mouse.y - rect.minY) <= abs(mouse.y - rect.maxY)
        return CGPoint(
            x: closerToMinX ? rect.maxX : rect.minX,
            y: closerToMinY ? rect.maxY : rect.minY
        )
    }
}
