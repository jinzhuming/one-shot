import CoreGraphics

public enum AnnotationHandle: String, CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

public enum AnnotationHitShape {
    case strokeRect(CGRect)
    case strokeEllipse(CGRect)
    case line(CGPoint, CGPoint)
    case polyline([CGPoint])
    case filledRect(CGRect)
    case filledEllipse(CGRect)
}

/// Pure geometry used by the annotation canvas. Coordinates are in the
/// screenshot's top-left, y-down space.
public enum AnnotationGeometry {
    public static func hitTest(
        point: CGPoint,
        shape: AnnotationHitShape,
        tolerance: CGFloat
    ) -> Bool {
        let tolerance = max(0, tolerance)
        switch shape {
        case .strokeRect(let rect):
            guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return !inner.contains(point) || !rect.contains(point)
                || point.x <= outer.minX || point.x >= outer.maxX
                || point.y <= outer.minY || point.y >= outer.maxY
        case .strokeEllipse(let rect):
            return ellipseDistance(point, rect: rect) <= tolerance
        case .line(let start, let end):
            return distance(point, toSegmentFrom: start, to: end) <= tolerance
        case .polyline(let points):
            guard points.count >= 2 else { return false }
            let smoothed = smoothedPath(points)
            return zip(smoothed, smoothed.dropFirst()).contains {
                distance(point, toSegmentFrom: $0, to: $1) <= tolerance
            }
        case .filledRect(let rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .filledEllipse(let rect):
            let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard expanded.width > 0, expanded.height > 0 else { return false }
            return ellipseContains(point, rect: expanded)
        }
    }

    public static func handle(
        at point: CGPoint,
        in rect: CGRect,
        tolerance: CGFloat
    ) -> AnnotationHandle? {
        let tolerance = max(0, tolerance)
        let candidates: [(AnnotationHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
        return candidates.first { distance(point, to: $0.1) <= tolerance }?.0
    }

    public static func movedRect(_ rect: CGRect, by delta: CGSize, inside bounds: CGRect) -> CGRect {
        let size = CGSize(
            width: min(rect.width, bounds.width),
            height: min(rect.height, bounds.height)
        )
        let origin = CGPoint(
            x: clamped(rect.minX + delta.width, lower: bounds.minX, upper: bounds.maxX - size.width),
            y: clamped(rect.minY + delta.height, lower: bounds.minY, upper: bounds.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    public static func resizedRect(
        _ original: CGRect,
        handle: AnnotationHandle,
        to point: CGPoint,
        preservingAspectRatio: Bool,
        inside bounds: CGRect,
        minimumSize: CGFloat = 3
    ) -> CGRect {
        guard original.width > 0, original.height > 0 else { return original }
        let point = CGPoint(
            x: clamped(point.x, lower: bounds.minX, upper: bounds.maxX),
            y: clamped(point.y, lower: bounds.minY, upper: bounds.maxY)
        )
        let movesLeft = [.topLeft, .left, .bottomLeft].contains(handle)
        let movesRight = [.topRight, .right, .bottomRight].contains(handle)
        let movesTop = [.topLeft, .top, .topRight].contains(handle)
        let movesBottom = [.bottomLeft, .bottom, .bottomRight].contains(handle)

        let anchorX = movesLeft ? original.maxX : original.minX
        let anchorY = movesTop ? original.maxY : original.minY
        var width = movesLeft || movesRight ? abs(point.x - anchorX) : original.width
        var height = movesTop || movesBottom ? abs(point.y - anchorY) : original.height
        width = max(minimumSize, width)
        height = max(minimumSize, height)

        if preservingAspectRatio && (movesLeft || movesRight) && (movesTop || movesBottom) {
            let ratio = original.width / original.height
            if abs(point.x - anchorX) / max(abs(point.y - anchorY), 0.001) > ratio {
                height = width / ratio
            } else {
                width = height * ratio
            }
        }

        var x = movesLeft ? anchorX - width : anchorX
        var y = movesTop ? anchorY - height : anchorY
        if x < bounds.minX { x = bounds.minX; width = anchorX - x }
        if y < bounds.minY { y = bounds.minY; height = anchorY - y }
        if x + width > bounds.maxX { width = bounds.maxX - x }
        if y + height > bounds.maxY { height = bounds.maxY - y }
        return CGRect(
            x: x,
            y: y,
            width: max(minimumSize, width),
            height: max(minimumSize, height)
        )
    }

    /// Removes high-frequency mouse jitter while retaining the original
    /// endpoints. The renderer turns the returned samples into a smooth path.
    public static func smoothedPath(
        _ points: [CGPoint],
        minimumDistance: CGFloat = 1.5
    ) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var filtered = [points[0]]
        var lastSample = points[0]
        for index in 1..<(points.count - 1) {
            let point = points[index]
            guard distance(point, to: lastSample) >= minimumDistance else { continue }
            let previous = points[index - 1]
            let next = points[index + 1]
            filtered.append(CGPoint(
                x: previous.x * 0.25 + point.x * 0.5 + next.x * 0.25,
                y: previous.y * 0.25 + point.y * 0.5 + next.y * 0.25
            ))
            lastSample = point
        }
        if let last = points.last, distance(last, to: filtered.last!) > 0.1 {
            filtered.append(last)
        }
        return filtered.count >= 2 ? filtered : [points[0], points[points.count - 1]]
    }

    public static func distance(_ a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    public static func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, to: start) }
        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(1, max(0, projection))
        return distance(point, to: CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }

    private static func ellipseContains(_ point: CGPoint, rect: CGRect) -> Bool {
        let dx = (point.x - rect.midX) / max(rect.width / 2, 0.001)
        let dy = (point.y - rect.midY) / max(rect.height / 2, 0.001)
        return dx * dx + dy * dy <= 1
    }

    private static func ellipseDistance(_ point: CGPoint, rect: CGRect) -> CGFloat {
        let outer = rect.insetBy(dx: -max(rect.width, rect.height), dy: -max(rect.width, rect.height))
        guard ellipseContains(point, rect: outer) else { return .greatestFiniteMagnitude }
        let dx = (point.x - rect.midX) / max(rect.width / 2, 0.001)
        let dy = (point.y - rect.midY) / max(rect.height / 2, 0.001)
        let normalized = abs(hypot(dx, dy) - 1)
        return normalized * min(rect.width, rect.height) / 2
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
